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
	//	private var reader:PacketParser;
		private var oldValue:Object=0;
		public function RemoteCallMgr()
		{
	//		reader = new PacketParser(onPacketRecv);
		}
		public function init():void
		{
	//		SerialDevice.sharedDevice().dataRecvSignal.add(__onSerialRecv);
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
			send();
		}
	/*
		private function __onSerialRecv(bytes:Array):void
		{
			reader.append(bytes);
		}
	*/
		private var value2:Object;
		public function onPacketRecv2(value:Object=null):void
		{
		//	onPacketRecv(value);
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
			send();
			oldValue = value||oldValue;
		}
		
		public function call(thread:Thread, method:String, param:Array, ext:ScratchExtension, retCount:int):void
		{
			var needSend:Boolean = (0 == requestList.length);
			requestList.push(arguments);
			if(needSend){
				send();
			}
		}
		
		private function send():void
		{
			if(requestList.length <= 0){
				return;
			}
			var info:Array = requestList[0];
			var ext:ScratchExtension = info[3];		// 
			var i:int;
			var obj1:Array;
			for(i = 0; i<ext.blockSpecs.length; i++) {
				if(ext.blockSpecs[i][2]==info[1]) {
					obj1 = ext.blockSpecs[i];
					break;
				}
			}
			var obj2:Object = obj1[obj1.length-1];

			if(obj2.hasOwnProperty("encode")) {
				switch(obj1[0]) {
				case 'w':
				case 'R':
				//	var param:Array;
					var param:Array = [0xff, 0x55, 0x00, 0x00, obj1[0]=='w'?2:1, obj2.encode[0]];
					for(i = 1; i < obj2.encode.length; i++) {
						var val:int=0;
						if(typeof info[2][i-1]=="string")
							val = ext.values[info[2][i-1]];
						else
							val = info[2][i-1];
						switch(obj2.encode[i]) {
						case 1:
							param.push(val)
							break;
						case 2:
							tempBytes.position = 0;
							tempBytes.writeShort(val);
							param.push(tempBytes[0]);
							param.push(tempBytes[1]);
							break;
						}
					}
					param[2] = param.length-3;
					ConnectionManager.sharedManager().send(param);
				//	ext.js.call('send', param, null);
					break;
				}
			} else {
				ext.js.call(info[1], info[2], null);	// runBuzzerJ2, [ド4, Half]
			}
			if(info[1].slice(0,9) == "runBuzzer")
			{
				timerId = setTimeout(onTimeout, 5000);
			}
			else
			{
				timerId = setTimeout(onTimeout, 500);
			}
		}
		static private const tempBytes:ByteArray = new ByteArray();
		tempBytes.endian = Endian.LITTLE_ENDIAN;
		
		private function onTimeout():void
		{
			if(requestList.length <= 0){
				return;
			}
			var info:Array = requestList[0];
			if(info[4] > 0){
				onPacketRecv(oldValue);
			}else{
				onPacketRecv();
			}
		}
	}
}