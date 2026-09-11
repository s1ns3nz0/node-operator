#!/usr/bin/env python3
import importlib.util, pathlib, unittest
PATH=pathlib.Path(__file__).resolve().parents[2]/"scripts/ops/lib/uc5-beacon-reader.py"; S=importlib.util.spec_from_file_location("b",PATH); M=importlib.util.module_from_spec(S); S.loader.exec_module(M)
KEY="0x"+"ab"*48
class T:
 def __init__(self): self.stopped=False; self.uid="pod-uid"
 def pod(self): return {"metadata":{"name":M.POD,"namespace":M.NS,"uid":self.uid}}
 def start(self,p): self.port=p; return self
 def ready(self,p,port): return True
 def poll(self): return None
 def stop(self,p): self.stopped=True
 def get(self,p,path):
  data={"/eth/v1/beacon/genesis":{"genesis_validators_root":M.GENESIS_ROOT,"genesis_time":str(M.GENESIS_TIME)},"/eth/v1/node/syncing":{"is_syncing":False,"is_optimistic":False,"el_offline":False,"sync_distance":"0"},"/eth/v1/beacon/states/head/validators/"+KEY:{"index":M.VALIDATOR_INDEX,"status":"active_ongoing","validator":{"pubkey":KEY}},"/eth/v1/beacon/headers/head":{"canonical":True,"header":{"message":{"slot":str((NOW-M.GENESIS_TIME)//12)}}}}; return {"data":data[path], "execution_optimistic":False} if path=="/eth/v1/beacon/headers/head" else {"data":data[path]}
NOW=M.GENESIS_TIME+1000
class Tests(unittest.TestCase):
 def test_ready_and_cleanup(self):
  t=T(); r=M.read_ready(KEY,t,lambda:NOW); self.assertEqual(r["result"],"PASS_PRIVATE_BEACON_READY"); self.assertTrue(t.stopped)
 def test_sync_validator_and_head_reject(self):
  for path,value in (("/eth/v1/node/syncing",{"is_syncing":True,"is_optimistic":False,"el_offline":False,"sync_distance":"0"}),("/eth/v1/beacon/states/head/validators/"+KEY,{"index":"1","status":"active_ongoing","validator":{"pubkey":KEY}})):
   t=T(); old=t.get
   def get(p,x,old=old,path=path,value=value): return {"data":value} if x==path else old(p,x)
   t.get=get
   with self.assertRaises(M.BeaconReaderError): M.read_ready(KEY,t,lambda:NOW)
   self.assertTrue(t.stopped)
 def test_startup_exit_and_redirect_refuse(self):
  t=T(); t.ready=lambda p,port: False
  with self.assertRaises(M.BeaconReaderError): M.read_ready(KEY,t,lambda:NOW)
  self.assertTrue(t.stopped)
  class Redirect(M._NoRedirect): pass
  with self.assertRaises(M.BeaconReaderError): Redirect().redirect_request(None,None,302,None,None,None)
if __name__=="__main__": unittest.main()
