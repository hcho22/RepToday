import {beforeEach,describe,expect,it,vi} from 'vitest';
import {premiumEntitlement} from '../src/coach-auth-crypto.js';
import {APP_PREFIX} from './auth-fixtures.js';

const {verify,lookup,verifierConstruct,clientConstruct}=vi.hoisted(()=>({
  verify:vi.fn(),lookup:vi.fn(),verifierConstruct:vi.fn(),clientConstruct:vi.fn(),
}));

// Trusted verifier/API workflow doubles; signature rejection is tested with the actual library in
// crypto and workerd suites. These payload fixtures can never authorize the published fetch entry.
vi.mock('@apple/app-store-server-library',()=>{
  const VerificationStatus={INVALID_ENVIRONMENT:4};
  class VerificationException extends Error {constructor(status){super('verification failed');this.status=status;}}
  return {
    Environment:{PRODUCTION:'Production',SANDBOX:'Sandbox',XCODE:'Xcode',LOCAL_TESTING:'LocalTesting'},
    VerificationStatus,VerificationException,
    SignedDataVerifier:class{
      constructor(...args){this.environment=args[2];verifierConstruct(...args);}
      verifyAndDecodeTransaction(proof){return verify(proof,this.environment,VerificationException,VerificationStatus);}
    },
    AppStoreServerAPIClient:class{
      constructor(...args){this.environment=args[4];clientConstruct(...args);}
      getAllSubscriptionStatuses(id){return lookup(id,this.environment);}
    },
  };
});

const now=1_800_000_000_000;
const transaction=(environment='Production')=>({bundleId:'com.reptoday.app',environment,type:'Auto-Renewable Subscription',
  productId:'com.reptoday.app.premium.monthly',transactionId:'1234',originalTransactionId:'1230',
  purchaseDate:now-1000,signedDate:now-500,expiresDate:now+1000});
const env={APP_STORE_APP_ID:'1',APP_STORE_KEY_ID:APP_PREFIX,APP_STORE_ISSUER_ID:'00000000-0000-4000-8000-000000000000',APP_STORE_PRIVATE_KEY:'TEST-ONLY-INVALID'};
let presented,current,statuses;

function select(environment='Production') {
  presented=transaction(environment);current=transaction(environment);
  statuses={bundleId:'com.reptoday.app',environment,appAppleId:1,
    data:[{lastTransactions:[{originalTransactionId:'1230',status:1,signedTransactionInfo:'current.proof.fixture'}]}]};
}

beforeEach(()=>{
  vi.clearAllMocks();select();
  verify.mockImplementation(async(proof,verifierEnvironment,VerificationException,VerificationStatus)=>{
    const value=proof==='current.proof.fixture'?current:presented;
    if(value.environment!==verifierEnvironment) throw new VerificationException(VerificationStatus.INVALID_ENVIRONMENT);
    return value;
  });
  lookup.mockImplementation(async()=>statuses);
});

describe('independent fresh Apple premium-status workflow',()=>{
  it('preserves the Production verifier, API and independently verified current-transaction flow',async()=>{
    await premiumEntitlement('presented.proof.fixture',env,()=>now);
    expect(verifierConstruct).toHaveBeenCalledTimes(1);
    expect(verifierConstruct.mock.calls[0][0]).toHaveLength(2);
    expect(verifierConstruct.mock.calls[0].slice(1)).toEqual([true,'Production','com.reptoday.app',1]);
    expect(clientConstruct.mock.calls[0].slice(1)).toEqual([APP_PREFIX,env.APP_STORE_ISSUER_ID,'com.reptoday.app','Production']);
    expect(verify.mock.calls.map(args=>[args[0],args[1]])).toEqual([
      ['presented.proof.fixture','Production'],['current.proof.fixture','Production'],
    ]);
    expect(lookup).toHaveBeenCalledWith('1230','Production');
  });

  it('selects Sandbox only from a typed verified environment mismatch and keeps the entire flow in Sandbox',async()=>{
    select('Sandbox');
    await premiumEntitlement('presented.proof.fixture',env,()=>now);
    expect(verifierConstruct).toHaveBeenCalledTimes(2);
    expect(verifierConstruct.mock.calls[0].slice(1)).toEqual([true,'Production','com.reptoday.app',1]);
    expect(verifierConstruct.mock.calls[1].slice(1)).toEqual([true,'Sandbox','com.reptoday.app']);
    expect(clientConstruct.mock.calls[0].slice(1)).toEqual([APP_PREFIX,env.APP_STORE_ISSUER_ID,'com.reptoday.app','Sandbox']);
    expect(verify.mock.calls.map(args=>[args[0],args[1]])).toEqual([
      ['presented.proof.fixture','Production'],['presented.proof.fixture','Sandbox'],['current.proof.fixture','Sandbox'],
    ]);
    expect(lookup).toHaveBeenCalledWith('1230','Sandbox');
  });

  it('never treats an arbitrary Production verification failure as Sandbox permission',async()=>{
    verify.mockRejectedValueOnce(new Error('private signed proof detail'));
    await expect(premiumEntitlement('presented.proof.fixture',env,()=>now)).rejects.toThrow('Coach authentication failed');
    expect(verifierConstruct).toHaveBeenCalledTimes(1);
    expect(verifierConstruct.mock.calls[0][2]).toBe('Production');
    expect(clientConstruct).not.toHaveBeenCalled();expect(lookup).not.toHaveBeenCalled();
  });

  it.each(['Production','Sandbox'])('never retries a %s API failure in another environment',async environment=>{
    select(environment);
    lookup.mockRejectedValue(new Error('private bearer/API detail'));
    await expect(premiumEntitlement('presented.proof.fixture',env,()=>now)).rejects.toThrow('Coach authentication failed');
    expect(verifierConstruct.mock.calls.map(args=>args[2])).toEqual(
      environment==='Production'?['Production']:['Production','Sandbox']);
    expect(clientConstruct.mock.calls.map(args=>args[4])).toEqual([environment]);
    expect(lookup).toHaveBeenCalledTimes(1);
  });

  it.each(['Xcode','LocalTesting','Unknown'])('keeps %s evidence unauthorized without an API lookup',async environment=>{
    select(environment);
    await expect(premiumEntitlement('presented.proof.fixture',env,()=>now)).rejects.toThrow('Coach authentication failed');
    expect(verifierConstruct.mock.calls.map(args=>args[2])).toEqual(['Production','Sandbox']);
    expect(clientConstruct).not.toHaveBeenCalled();expect(lookup).not.toHaveBeenCalled();
  });

  it.each([2,3,4,5,6])('expired/retry/grace/revoked/unknown status %d denies premium',async status=>{
    for(const environment of ['Production','Sandbox']) {
      select(environment);statuses.data[0].lastTransactions[0].status=status;
      await expect(premiumEntitlement('presented.proof.fixture',env,()=>now)).rejects.toThrow();
    }
  });

  it.each(['bundleId','environment','appAppleId'])('rejects substituted or missing server %s in both environments',async field=>{
    for(const environment of ['Production','Sandbox']) {
      select(environment);statuses[field]=undefined;
      await expect(premiumEntitlement('presented.proof.fixture',env,()=>now)).rejects.toThrow();
    }
  });

  it('rejects mixed status/current environments without trying another API environment',async()=>{
    select('Sandbox');statuses.environment='Production';
    await expect(premiumEntitlement('presented.proof.fixture',env,()=>now)).rejects.toThrow();
    expect(clientConstruct.mock.calls.map(args=>args[4])).toEqual(['Sandbox']);expect(lookup).toHaveBeenCalledTimes(1);
    select('Sandbox');current=transaction('Production');
    await expect(premiumEntitlement('presented.proof.fixture',env,()=>now)).rejects.toThrow();
    expect(clientConstruct.mock.calls.map(args=>args[4])).toEqual(['Sandbox','Sandbox']);expect(lookup).toHaveBeenCalledTimes(2);
  });

  it('rejects duplicate chain records and transaction substitution',async()=>{
    for(const environment of ['Production','Sandbox']) {
      select(environment);statuses.data[0].lastTransactions.push({...statuses.data[0].lastTransactions[0]});
      await expect(premiumEntitlement('presented.proof.fixture',env,()=>now)).rejects.toThrow();
      statuses.data[0].lastTransactions.pop();current={...current,originalTransactionId:'9999'};
      await expect(premiumEntitlement('presented.proof.fixture',env,()=>now)).rejects.toThrow();
    }
  });

  it('applies bundle, product, type, expiry, revocation and upgrade checks to both verified transactions',async()=>{
    const mutations=[['bundleId','other.app'],['productId','other.premium'],['type','Non-Consumable'],
      ['expiresDate',now],['revocationDate',now-1],['isUpgraded',true]];
    for(const environment of ['Production','Sandbox'])
      for(const boundary of ['presented','current']) for(const [field,value] of mutations) {
        select(environment);
        if(boundary==='presented') presented={...presented,[String(field)]:value}; else current={...current,[String(field)]:value};
        await expect(premiumEntitlement('presented.proof.fixture',env,()=>now)).rejects.toThrow();
      }
  });

  it('latest-proof verification failure denies without leaking diagnostics',async()=>{
    verify.mockImplementationOnce(async()=>presented).mockRejectedValueOnce(new Error('private JWS detail'));
    await expect(premiumEntitlement('presented.proof.fixture',env,()=>now)).rejects.toThrow('Coach authentication failed');
  });
});
