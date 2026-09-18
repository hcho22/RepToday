import {beforeEach,afterEach,describe,expect,it,vi} from 'vitest';
import {premiumEntitlement} from '../src/coach-auth-crypto.js';
import {APP_PREFIX} from './auth-fixtures.js';
const {verify,lookup,construct}=vi.hoisted(()=>({verify:vi.fn(),lookup:vi.fn(),construct:vi.fn()}));
// Trusted verifier/API workflow doubles; signature rejection is tested with the actual library in
// crypto and workerd suites. These payload fixtures can never authorize the published fetch entry.
vi.mock('@apple/app-store-server-library',()=>({Environment:{PRODUCTION:'Production'},
  SignedDataVerifier:class{constructor(...args){construct(...args);}verifyAndDecodeTransaction=verify;},
  AppStoreServerAPIClient:class{getAllSubscriptionStatuses=lookup;}}));
const now=1_800_000_000_000;
const transaction=()=>({bundleId:'com.reptoday.app',environment:'Production',type:'Auto-Renewable Subscription',
  productId:'com.reptoday.app.premium.monthly',transactionId:'1234',originalTransactionId:'1230',
  purchaseDate:now-1000,signedDate:now-500,expiresDate:now+1000});
const env={APP_STORE_APP_ID:'1',APP_STORE_KEY_ID:APP_PREFIX,APP_STORE_ISSUER_ID:'00000000-0000-4000-8000-000000000000',APP_STORE_PRIVATE_KEY:'TEST-ONLY-INVALID'};
let statuses;
beforeEach(()=>{
  vi.clearAllMocks();statuses={bundleId:'com.reptoday.app',environment:'Production',appAppleId:1,
    data:[{lastTransactions:[{originalTransactionId:'1230',status:1,signedTransactionInfo:'current.proof.fixture'}]}]};
  verify.mockResolvedValue(transaction());lookup.mockImplementation(async()=>statuses);
});afterEach(()=>vi.restoreAllMocks());
describe('independent fresh Apple premium-status workflow',()=>{
  it('verifies both supplied/latest transactions with production trust/online checks and a fresh server lookup',async()=>{
    await premiumEntitlement('presented.proof.fixture',env,()=>now);
    expect(construct.mock.calls[0][0]).toHaveLength(2);expect(construct.mock.calls[0].slice(1)).toEqual([true,'Production','com.reptoday.app',1]);
    expect(verify.mock.calls.map(args=>args[0])).toEqual(['presented.proof.fixture','current.proof.fixture']);
    expect(lookup).toHaveBeenCalledWith('1230');
  });
  it('unverified supplied proof cannot cause subscription lookup',async()=>{
    verify.mockRejectedValue(new Error('private signed proof detail'));
    await expect(premiumEntitlement('presented.proof.fixture',env,()=>now)).rejects.toThrow('Coach authentication failed');
    expect(lookup).not.toHaveBeenCalled();
  });
  it.each([2,3,4,5])('expired/retry/grace/revoked status %d denies premium',async status=>{
    statuses.data[0].lastTransactions[0].status=status;await expect(premiumEntitlement('presented.proof.fixture',env,()=>now)).rejects.toThrow();
  });
  it.each(['bundleId','environment','appAppleId'])('rejects substituted server %s',async field=>{
    statuses[field]='foreign';await expect(premiumEntitlement('presented.proof.fixture',env,()=>now)).rejects.toThrow();
  });
  it('rejects duplicate chain records and transaction substitution',async()=>{
    statuses.data[0].lastTransactions.push({...statuses.data[0].lastTransactions[0]});
    await expect(premiumEntitlement('presented.proof.fixture',env,()=>now)).rejects.toThrow();
    statuses.data[0].lastTransactions.pop();verify.mockResolvedValueOnce(transaction()).mockResolvedValueOnce({...transaction(),originalTransactionId:'9999'});
    await expect(premiumEntitlement('presented.proof.fixture',env,()=>now)).rejects.toThrow();
  });
  it('API failure and latest-proof verification failure both deny without leaking diagnostics',async()=>{
    lookup.mockRejectedValue(new Error('private bearer/API detail'));
    await expect(premiumEntitlement('presented.proof.fixture',env,()=>now)).rejects.toThrow('Coach authentication failed');
    lookup.mockResolvedValue(statuses);verify.mockResolvedValueOnce(transaction()).mockRejectedValueOnce(new Error('private JWS detail'));
    await expect(premiumEntitlement('presented.proof.fixture',env,()=>now)).rejects.toThrow('Coach authentication failed');
  });
  it.each(['Sandbox','Xcode','LocalTesting'])('retained production workflow rejects %s in either independently verified transaction',async environment=>{
    for (const boundary of ['presented','current']) {
      verify.mockReset();
      verify.mockResolvedValueOnce({...transaction(),environment:boundary==='presented'?environment:'Production'})
        .mockResolvedValueOnce({...transaction(),environment:boundary==='current'?environment:'Production'});
      await expect(premiumEntitlement('presented.proof.fixture',env,()=>now)).rejects.toThrow('Coach authentication failed');
      expect(construct.mock.calls.every(args=>args[2]==='Production')).toBe(true);
    }
  });
});
