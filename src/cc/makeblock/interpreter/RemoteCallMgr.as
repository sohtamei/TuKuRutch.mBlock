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
		private var timerId:uint;
		private var oldValue:Object=0;
		public function RemoteCallMgr()
		{
		}
		public function init():void
		{
		}
	
		public function interruptThread():void
		{
			if(requestList.length <= 0){
				return;
			}
			var info:Array = requestList.shift();
			var thread:Thread = info[0];
			thread.interrupt();
			clearTimeout(timerId);
		//	send();
		}
		private var value2:Object;
		public function onPacketRecv2(value:Object=null):void
		{
			value2 = value;
			setTimeout(onTimeout2, 0);
		}
		private function onTimeout2():void
		{
			onPacketRecv(value2);
		}

		public function onPacketRecv(value:Object=null):void
		{
			if(requestList.length <= 0){
				return;
			}
			var info:Array = requestList.shift();
			var thread:Thread = info[0];
			if(thread != null){
				if(info[4] > 0){
					if(arguments.length > 0){
						thread.push(value);
					}else{
						thread.push(0);
					}
				}
				thread.resume();
			}
			clearTimeout(timerId);
		//	send();
			oldValue = value||oldValue;
		}
		
		public function call(thread:Thread, method:String, param:Array, ext:ScratchExtension, retCount:int):void
		{
			var index:int;
			var obj1:Array;
			for(index = 0; index<ext.blockSpecs.length; index++) {
				if(ext.blockSpecs[index][2]==method) {
					obj1 = ext.blockSpecs[index];
					break;
				}
			}
			if(obj1==null) return;

			var i:int;
			for(i = 0; i < param.length; i++) {
				if(typeof param[i]=="string")
					param[i] = ext.values[param[i]];
			}

			var obj2:Object = obj1[obj1.length-1];
			if(obj2.hasOwnProperty("enum")) {
				thread.push(param[0]);
			//	onPacketRecv2(val);
				return;
			}

			if(obj2.hasOwnProperty("remote")) {
				var cmd:ByteArray = new ByteArray();
				cmd.endian = Endian.LITTLE_ENDIAN;
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
					}
				}
				cmd[2] = cmd.length-3;
				thread.suspend();
				requestList.push(arguments);
				Main.app.scriptsPart.onSerialSend(cmd);	// debug
				ConnectionManager.sharedManager().sendBytes(cmd);
			} else if(obj2.hasOwnProperty("custom")) {
				thread.suspend();
				requestList.push(arguments);
				ext.js.call(method, param, null);	// runBuzzerJ2, [ド4, Half]
			}
			if(method.slice(0,6) == "Buzzer") {
				timerId = setTimeout(onTimeout, 5000);
			} else {
				timerId = setTimeout(onTimeout, 500);
			}
		}
		
		private function onTimeout():void
		{
			if(requestList.length <= 0){
				return;
			}
			var info:Array = requestList[0];
			if(info[4] > 0){	// retcount
				onPacketRecv(oldValue);
			}else{
				onPacketRecv();
			}
		}
	}
}