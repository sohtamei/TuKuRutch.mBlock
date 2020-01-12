package cc.makeblock.interpreter
{
	import blockly.runtime.FunctionProvider;
	import blockly.runtime.Thread;
	
	import blocks.Block;
	
	import cc.makeblock.util.StringChecker;
	
//	import extensions.ParseManager;
	
	import interpreter.Variable;
	
	import scratch.ScratchObj;
	
	internal class PrimInit
	{
		static public function Init(provider:FunctionProvider):void
		{
			provider.alias("sleep", "wait:elapsed:from:");
			provider.register("broadcast:", doBroadcast);
			provider.register("doBroadcastAndWait", doBroadcastAndWait);
			provider.register("stopAll", stopAll);
			provider.register("stopScripts", stopScripts);
			provider.register("suspendUntilNextFrame", onSuspendUntilNextFrame);
			provider.register("getUserName", onGetUserName);
			
			provider.register(Specs.GET_VAR, doGetVar);
			provider.register(Specs.SET_VAR, doSetVar);
			provider.register(Specs.CHANGE_VAR, increaseVar);
		}
		
		static private function onGetUserName(thread:Thread, argList:Array):void
		{
			thread.push("Player1");
		}
		
		static private function onSuspendUntilNextFrame(thread:Thread, argList:Array):void
		{
			if(!Main.app.interp.turboMode){
				thread.suspendUntilNextFrame();
			}
		}
		
		static private function broadcast(thread:Thread, msg:String, waitFlag:Boolean):void
		{
//			ParseManager.sharedManager().parse("serial/line/"+msg);
//			if (target.activeThread.firstTime) {
			var receivers:Array = [];
			msg = msg.toLowerCase();
			function findReceivers(stack:Block, obj:ScratchObj):void {
				//有个sb2文件随便一点都会报错，这里先加个catch处理  by谭启亮 20161123
				try{
					if ((stack.op == "whenIReceive") && (stack.args[0].argValue.toLowerCase() == msg)) {
						receivers.push([stack, obj]);
					}
				}
				catch(err:Error)
				{
					trace("error come");
				}
				
			}
			Main.app.runtime.allStacksAndOwnersDo(findReceivers);
			var threadList:Array = [];
			for each(var item:Array in receivers){
				var newThread:Thread = Main.app.interp.toggleThread(item[0], item[1]);
				threadList.push(newThread);
			}
//			target.startAllReceivers(receivers, waitFlag);
			if(waitFlag){
				thread.suspend();
				thread.suspendUpdater = [checkSubThreadFinish, threadList];
			}
		}
		
		static public function checkSubThreadFinish(thread:Thread, threadList:Array):void
		{
			for each(var t:Thread in threadList){
				if(!t.isFinish()){
					return;
				}
			}
			thread.resume();
		}
		
		static private function doBroadcast(thread:Thread, argList:Array):void
		{
			broadcast(thread, argList[0], false);
		}
		
		static private function doBroadcastAndWait(thread:Thread, argList:Array):void
		{
			broadcast(thread, argList[0], true);
		}
		
		static private function stopScripts(thread:Thread, argList:Array):void
		{
			switch(argList[0])
			{
				case "all":
					Main.app.runtime.stopAll();
					break;
				case "this script":
					thread.interrupt();
					break;
				case "other scripts in sprite":
				case "other scripts in stage":
					BlockInterpreter.Instance.stopObjOtherThreads(thread);
					break;
			}
		}
		static private function getVarRealVal(val:*):*
		{
			var result:* = val;
			if(val is String && StringChecker.IsNumber(val)){
				return parseFloat(val);
			}
			return result;
		}
		
		static private function doGetVar(thread:Thread, argList:Array):void
		{
			var target:ScratchObj = ThreadUserData.getScratchObj(thread);
			var v:Variable = target.varCache[argList[0]];
			if(v != null){
				// XXX: Do we need a get() for persistent variables here ?
				thread.push(getVarRealVal(v.value));
				return;
			}
			v = target.varCache[argList[0]] = target.lookupOrCreateVar(argList[0]);
			thread.push( (v != null) ? getVarRealVal(v.value) : 0);
		}
		
		static private function doSetVar(thread:Thread, argList:Array):void
		{
			var target:ScratchObj = ThreadUserData.getScratchObj(thread);
			var v:Variable = target.varCache[argList[0]];
			if (!v) {
				v = target.varCache[argList[0]] = target.lookupOrCreateVar(argList[0]);
				if (!v){
					return;
				}
			}
			v.value = argList[1];
		}
		
		static private function increaseVar(thread:Thread, argList:Array):void
		{
			var target:ScratchObj = ThreadUserData.getScratchObj(thread);
			var v:Variable = target.varCache[argList[0]];
			if (!v) {
				v = target.varCache[argList[0]] = target.lookupOrCreateVar(argList[0]);
				if (!v){
					return;
				}
			}
			v.value = Number(v.value) + Number(argList[1]);
		}
		
		static private function stopAll(thread:Thread, argList:Array):void
		{
			Main.app.runtime.stopAll();
		}
	}
}