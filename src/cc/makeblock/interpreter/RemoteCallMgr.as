package cc.makeblock.interpreter
{
	import flash.utils.clearTimeout;
	import flash.utils.setTimeout;
	import flash.utils.ByteArray;
	import flash.utils.Endian;
	
	import blockly.runtime.Thread;
	
	import extensions.ScratchExtension;
	import extensions.ConnectionManager;

	public class RemoteCallMgr
	{
		static public const Instance:RemoteCallMgr = new RemoteCallMgr();
		
		private const requestList:Array = [];
		private var timerId:uint = uint(-1);
		public function RemoteCallMgr()
		{
		}
		public function init():void
		{
		}
/*
		private function log(mes:String):void
		{
			mes += ":"+requestList.length;
			if(requestList.length)
				mes += "-"+requestList[0][1];
			Main.app.track(mes);
		}
*/
		public function interruptThread():void
		{
			if(requestList.length <= 0){
				return;
			}
			var info:Array = requestList.shift();
			var thread:Thread = info[0];
			if(thread.userData) trace(thread.userData.block.op+"-interruptThread");
			thread.interrupt();
			clearTimeout(timerId);
		}
		public function onPacketRecv2(value:Object=null):void
		{
			var value2:Object = value;
			setTimeout(onTimeout2, 0);

			function onTimeout2():void
			{
				onPacketRecv(value2);
			}
		}

		public function onPacketRecv(value:Object=null):void
		{
			if(requestList.length <= 0){
				return;
			}
			var info:Array = requestList.shift();
			var thread:Thread = info[0];
			if(thread.userData) trace(thread.userData.block.op+"-onPacketRecv");
			if(thread != null){
				if(info[4] > 0){
					if(arguments.length > 0){
						thread.push(value);
						Main.app.track("ret="+value);
					}else{
						thread.push(0);
					}
				}
				thread.resume();
			}
			clearTimeout(timerId);
		}

		// Block/doubleClick
		// interpreter:Interpreter/toggleThread - runThread
		// interpreter:BlockInterpreter/execute
		// blockly:runtime:Interpreter/execute
		// Event.ENTER_FRAME (VirtualMachine)
		// VirtualMachine/onUpdateThreads    while(updateThreads() && getTimer() < endTime);
		// Thread/execNextCode
		// InstructionExector/execute(thread, op, argList) argList.unshift(thread)
		// regOpHandler(OpCode.CALL, __onCall);
		// InstructionExector/__onCall()
		// FunctionProvider/execute(thread, name:robot.localIpWifi, argList:[], retCount:1)
		// ArduinoFunctionProvider/onCallUnregisteredFunction(thread, name, argList, retCount)

		// # remote
		// call
		//		thread.suspend();
		//		requestList.push(arguments);
		//		ConnectionManager/sendBytes(cmd);
		//		----
		//		robot.js/processData - JavaScriptEngine/responseValue - onPacketRecv
		//		info = requestList.shift();
		//		thread = info[0];
		//		thread.push(value);
		//		thread.resume();

		// VirtualMachine/onUpdateThreads
		// thread.finishSignal
		// Thread/notifyFinish - Signal/notify
		// Interpreter/thread.finishSignal

		// # custom
		// call
		//		thread.suspend();
		//		requestList.push(arguments);
		//		ext.js.call - robot.js/ext.getRemoteX - JavaScriptEngine/responseValue2 - onPacketRecv2
		//		setTimeout
		//		----
		//		info = requestList.shift();
		//		thread = info[0];
		//		thread.push(value);
		//		thread.resume();

		// # enum
		// call
		//		thread.push(param[0]);

		public function call(thread:Thread, method:String, param:Array, ext:ScratchExtension, retCount:int):void
		{
			if(thread.userData) trace(thread.userData.block.op+"-call "+method);
			var index:int;
			var obj1:Array;
			for(index = 0; index<ext.blockSpecs.length; index++) {
				if(ext.blockSpecs[index][2]==method) {
					obj1 = ext.blockSpecs[index];
					break;
				}
			}
			if(obj1==null) return;
			if(timerId != uint(-1)) clearTimeout(timerId);

			var i:int;
			var obj2:Object = obj1[obj1.length-1];
			if(obj2.hasOwnProperty("enum")) {
				if(typeof param[0]=="string")
					param[0] = ext.values[param[0]];
				thread.push(param[0]);
				return;
			}

			if(obj2.hasOwnProperty("remote")) {
				var blockDefs:Array = obj1[1].split("%");
				for(i = 0; i < param.length; i++) {
					//  %d-数値+enum, %m-文字列+enumのときvaluesで置換
					if(i+1 < blockDefs.length) {
						var argType:String = blockDefs[i+1].charAt(0);
						if(argType == "d" || argType == "m") {
							if(typeof param[i]=="string" && ext.values[param[i]] != undefined)
								param[i] = ext.values[param[i]];
						}
					}
				}

				var cmd:ByteArray = new ByteArray();
				cmd.endian = Endian.LITTLE_ENDIAN;
				var n:int;
				var j:int;
				if(obj2.remote[0] == "b2") {
					n = param[0].length/2;
					cmd.writeByte(0xff);
					cmd.writeByte(0x54);
					cmd.writeShort(1+n);
					cmd.writeByte(index);
					for(j = 0; j < n; j++)
						cmd.writeByte(parseInt(param[0].substr(j*2, 2),16));
				} else {
					var tmp:Array = [0xff, 0x55, 0x00, index];
					for(i = 0; i < tmp.length; i++)
						cmd.writeByte(tmp[i]);
					var size:int = obj2.remote.length;
					if(obj1[0] != "w") size--;
					for(i = 0; i < size; i++) {
						switch(obj2.remote[i]) {
						case "B": cmd.writeByte(param[i]);   break;
						case "S": cmd.writeShort(param[i]);  break;
						case "L": cmd.writeInt(param[i]);    break;
						case "F": cmd.writeFloat(param[i]);  break;
						case "D": cmd.writeDouble(param[i]); break;
						case "s": cmd.writeUTFBytes(param[i]); cmd.writeByte(0); break;
						case "b":
							n = param[i].length/2;
							cmd.writeByte(n);
							for(j = 0; j < n; j++)
								cmd.writeByte(parseInt(param[i].substr(j*2, 2),16));
							break;
						}
					}
					cmd[2] = cmd.length-3;
				}
				thread.suspend();
				requestList.push(arguments);
				Main.app.scriptsPart.onSerialSend(cmd);	// debug
				ConnectionManager.sharedManager().sendBytes(cmd);
			} else if(obj2.hasOwnProperty("custom")) {
				for(i = 0; i < param.length; i++) {
					if(obj2.custom.length <= i || obj2.custom[i]!="s") {
						if(typeof param[i]=="string")
							param[i] = ext.values[param[i]];
					}
				}

				thread.suspend();
				requestList.push(arguments);
				ext.js.call(method, param, null);	// runBuzzerJ2, [ド4, Half]
			}
			if(method.slice(0,6) == "Buzzer"||method == "scanWifi"||method == "connectWifi") {
				timerId = setTimeout(onTimeout, 10000);//5000);
			} else {
				timerId = setTimeout(onTimeout, 2000);
			}

			function onTimeout():void
			{
				if(requestList.length <= 0){
					return;
				}
				var info:Array = requestList[0];
				if(info[0].userData) trace(info[0].userData.block.op+"-onTimeout");
				if(info[4] > 0){	// retcount
					onPacketRecv("");
				}else{
					onPacketRecv();
				}
			}
		}

		public function clear():void
		{
			requestList.splice(0,requestList.length);
			clearTimeout(timerId);
		}
	}
}