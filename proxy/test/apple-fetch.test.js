import {afterEach,describe,expect,it,vi} from 'vitest';
import appleFetch from '../src/apple-fetch.js';
afterEach(()=>vi.unstubAllGlobals());
describe('bounded official-verifier HTTP transport',()=>{
  it.each(['https://api.storekit.itunes.apple.com/inApps/v1/subscriptions/1',
    'https://api.storekit.apple.com/inApps/v1/subscriptions/1?foreign=1','https://attacker.invalid/','https://api.storekit.apple.com/inApps/v1/subscriptions/1/extra',
    'https://api.storekit-sandbox.apple.com/inApps/v1/subscriptions/1',
    'https://user:password@api.storekit.apple.com/inApps/v1/subscriptions/1',
    'https://api.storekit.apple.com/inApps/v1/subscriptions/1#extra'])('rejects unapproved origin/path before egress',async url=>{
    const fetch=vi.fn();vi.stubGlobal('fetch',fetch);await expect(appleFetch(url)).rejects.toThrow();expect(fetch).not.toHaveBeenCalled();
  });
  it('restricts methods and disables redirects with a total resource deadline',async()=>{
    const fetch=vi.fn(async(_url,_options)=>new Response('{}'));vi.stubGlobal('fetch',fetch);
    await appleFetch('https://api.storekit.apple.com/inApps/v1/subscriptions/1');
    expect(fetch.mock.calls[0][1].redirect).toBe('manual');expect(fetch.mock.calls[0][1].signal).toBeInstanceOf(AbortSignal);
    await expect(appleFetch('https://api.storekit.apple.com/inApps/v1/subscriptions/1',{method:'POST'})).rejects.toThrow();
  });
  it.each([300,301,302,303,304,305,306,307,308,399])('rejects status %i without reading or following a redirect',async status=>{
    const read=vi.fn();const cancel=vi.fn(async()=>{});
    const fetch=vi.fn(async(_url,_options)=>({status,redirected:false,body:{getReader:read,cancel},
      headers:new Headers({Location:'https://attacker.invalid/'})}));
    vi.stubGlobal('fetch',fetch);
    await expect(appleFetch('https://api.storekit.apple.com/inApps/v1/subscriptions/1',{redirect:'follow'})).rejects.toThrow('Apple verification unavailable');
    expect(fetch).toHaveBeenCalledTimes(1);expect(fetch.mock.calls[0][1].redirect).toBe('manual');
    expect(read).not.toHaveBeenCalled();expect(cancel).toHaveBeenCalledTimes(1);
  });
  it('rejects an already-redirected response even if its status is successful',async()=>{
    const cancel=vi.fn(async()=>{});const read=vi.fn();
    vi.stubGlobal('fetch',async()=>({status:200,redirected:true,body:{getReader:read,cancel}}));
    await expect(appleFetch('https://api.storekit.apple.com/inApps/v1/subscriptions/1')).rejects.toThrow();
    expect(read).not.toHaveBeenCalled();expect(cancel).toHaveBeenCalledTimes(1);
  });
  it.each([['https://api.storekit.apple.com/inApps/v1/subscriptions/1','GET',65536],['http://ocsp.apple.com/fixture','POST',16384]])('bounds API and OCSP streamed bodies',async(url,method,max)=>{
    vi.stubGlobal('fetch',async()=>new Response(new Uint8Array(Number(max))));
    const result=await appleFetch(String(url),{method:String(method)});expect((await result.buffer()).length).toBe(max);
    vi.stubGlobal('fetch',async()=>new Response(new Uint8Array(Number(max)+1)));
    await expect(appleFetch(String(url),{method:String(method)})).rejects.toThrow();
  });
  it('honors abort while reading a delayed response body',async()=>{
    vi.stubGlobal('fetch',async(_,options)=>new Response(new ReadableStream({start(controller){
      options.signal.addEventListener('abort',()=>controller.error(new Error('timed out')),{once:true});
    }})));
    const start=Date.now();await expect(appleFetch('http://ocsp.apple.com/fixture',{method:'POST'})).rejects.toThrow();
    expect(Date.now()-start).toBeLessThan(3500);
  });
});
