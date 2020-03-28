package extensions
{
	import flash.desktop.NativeProcess;
	import flash.desktop.NativeProcessStartupInfo;
	import flash.events.Event;
	import flash.events.EventDispatcher;
	import flash.events.NativeProcessExitEvent;
	import flash.events.ProgressEvent;
	import flash.events.TimerEvent;
	import flash.filesystem.File;
	import flash.utils.ByteArray;
	import flash.utils.Timer;
	import flash.utils.setTimeout;
	import cc.makeblock.interpreter.BlockInterpreter;
//	import cc.makeblock.util.UploadSizeInfo;
	
	import translation.Translator;
	
	import uiwidgets.DialogBox;
	
	import util.ApplicationManager;

	import blockly.signals.Signal;

	public class ConnectionManager extends EventDispatcher
	{
		private static var _instance:ConnectionManager;
		private var _serial:AIRSerial;

		public var selectPort:String = "";		// 選択中の "COMx"
		private var _receiveHandler:Function=null;

		private var _mBlock:Main;
		private var _dialog:DialogBox = new DialogBox();
			
//		private var _isMacOs:Boolean = ApplicationManager.sharedManager().system==ApplicationManager.MAC_OS;
//		private var _avrdude:String = "";
//		private var _avrdudeConfig:String = "";

		public static function sharedManager():ConnectionManager{
			if(_instance==null){
				_instance = new ConnectionManager;
			}
			return _instance;
		}

		public function ConnectionManager()
		{
			_serial = new AIRSerial();
//			_avrdude = _isMacOs?"avrdude":"avrdude.exe";
//			_avrdudeConfig = _isMacOs?"avrdude_mac.conf":"avrdude.conf";

			var timer:Timer = new Timer(4000);
			timer.addEventListener(TimerEvent.TIMER, onTimerCheck);
			timer.start();

			function cancel():void { _dialog.cancel(); }
			_dialog.addTitle(Translator.map('Start Uploading'));
			_dialog.addButton(Translator.map('Close'), cancel);
		}
		private function onTimerCheck(evt:TimerEvent):void{
			if(_serial.isConnected){
				if(this.portlist.indexOf(selectPort) == -1)
					onClose();
			}
		}
		public function setMain(mBlock:Main):void{
			_mBlock = mBlock;
		}

		// list

		public function get portlist():Array{
			var _currentList:Array = [];
			try{
				_currentList = formatArray(_serial.list().split(",").sort());
				var emptyIndex:int = _currentList.indexOf("");
				if(emptyIndex>-1){
					_currentList.splice(emptyIndex, emptyIndex+1);
				}
			}catch(e:*){
			}
			return _currentList;
		}

		private function formatArray(arr:Array):Array {
			var obj:Object={};
			return arr.filter(
				function(item:*, index:int, array:Array):Boolean{
					return !obj[item] ? obj[item]=true: false
				}
			);
		}

		// open

		// 0. 										- addEventListener(Event.CONNECT, onConnected)
		// 1. onConnect("serial_COM3")				- setTimeout(onOpen, 100, "COM3")
		// 2. onOpen("COM3)							- Event.CONNECT
		// 3. onConnected (JavaScriptEngine.as)
		// 4. _deviceConnected (robot.js)
		// 5. open(115200, deviceOpened)
		// 6. deviceOpened (robot.js, checkDevName)	- set_receive_handler(processData)

		public function onConnect(port:String):void{
			BlockInterpreter.Instance.stopAllThreads();
			if(selectPort==port && _serial.isConnected){
				onClose();
			}else{
				if(_serial.isConnected)
					onClose();
				setTimeout(onOpen, 100, port);
			}
		}

		public function onOpen(port:String):void{
			selectPort = port;
			this.dispatchEvent(new Event(Event.CONNECT));
		}

		public function open(baud:uint, openedHandle:Function):void{
			Main.app.track("connection:"+selectPort);
			if(_serial.isConnected)
				_serial.close();
			_serial.addEventListener(Event.CHANGE, onChanged);
			var r:uint = _serial.open(selectPort,baud);
			ArduinoManager.sharedManager().isUploading = false;
			if(r==0){
				Main.app.topBarPart.setConnectedButton(true);

				var checkDevName:Boolean = true;
				var boards:Array = Main.app.extensionManager.extensionByName().boardType.split(":");
				switch(boards[1]) {
				case "samd":
				case "esp32":
					checkDevName = false;
					break;
				}
				openedHandle(this, checkDevName);
				removeEventListener(Event.CHANGE,_onReceived);
				addEventListener(Event.CHANGE,_onReceived);
			}else{
				onClose();
			}
		}

		public function set_receive_handler(receiveHandler:Function):void{
			_receiveHandler = receiveHandler;
		}

		public function onRemoved(extName:String = ""):void{
			this.dispatchEvent(new Event(Event.REMOVED));
		}

		public function onReOpen():void{
			if(selectPort != "")
				this.dispatchEvent(new Event(Event.CONNECT));
		}

		public function update():void{
			Main.app.topBarPart.setConnectedButton(_serial.isConnected);
		}

		// close

		// 1. onConnect("serial_COM3")
		// 2. onClose								- Event.CLOSE
		// 4. onClosed (JavaScriptEngine.as)
		// 5. _deviceRemoved (robot.js)

		public function onClose():void{
			if(_serial.isConnected){
				BlockInterpreter.Instance.stopAllThreads();
				ArduinoManager.sharedManager().isUploading = false;
				_serial.removeEventListener(Event.CHANGE, onChanged);
				_serial.close();
				_receiveHandler = null;
				Main.app.topBarPart.setConnectedButton(false);
				this.dispatchEvent(new Event(Event.CLOSE));
			}
		}
/*
		public function __close():void{
			ConnectionManager.sharedManager().close();
		}
*/
		// recv

		// 0.								- Event.CHANGE (_serial)
		// 1. onChanged						- Event.CHANGE
		// 2. _onReceived					- _receiveHandler = processData(_receivedBytes)
		// 3. processData (robot.js)		- responseValue(JavaScriptEngine) - onPacketRecv(RemoteCallMgr) - thread.push&thread.resume

		private var _bytes:ByteArray;
		private function onChanged(evt:Event):void{
			var len:uint = _serial.getAvailable();
			if(len>0){
				_bytes = _serial.readBytes();
				Main.app.scriptsPart.onSerialDataReceived(_bytes);	// debug
				this.dispatchEvent(new Event(Event.CHANGE));
			}
			return;
		}

		private function _onReceived(evt:Event):void
		{
			var _receivedBytes:Array = [];
			_bytes.position=0;
			while(_bytes.bytesAvailable > 0){
				_receivedBytes.push(_bytes.readUnsignedByte());
			}
			_bytes.clear();

			if(_receiveHandler != null && _receivedBytes.length > 0){
				try{
					_receiveHandler(_receivedBytes);
				}catch(err:*){
					trace(err);
				}
				return;
			}
		}

		// send
	
		public function send(bytes:Array):void{
			var buffer:ByteArray = new ByteArray();
			for(var i:int=0;i<bytes.length;i++){
				buffer[i] = bytes[i];
			}
			Main.app.scriptsPart.onSerialSend(buffer);	// debug
			sendBytes(buffer);
		}
		public function sendBytes(bytes:ByteArray):void{
			if(_serial.isConnected){
				_serial.writeBytes(bytes);
			}
			bytes.clear();
		}
	/*
		public function sendString(msg:String):int{
			return _serial.writeString(msg);
		}
		public function readBytes():ByteArray{
			var len:uint = _serial.getAvailable();
			if(len>0){
				return _serial.readBytes();
			}
			return new ByteArray;
		}
	*/
		public function get isConnected():Boolean{
			return _serial.isConnected;
		}
/*
		public function reconnectSerial():void{
			if(_serial.isConnected){
				_serial.close();
				setTimeout(function():void{connect(currentPort);},50);
				//setTimeout(function():void{_serial.close();},1000);
			}
		}
*/
		// update

		public function burnFW(hexFile:String):void
		{
			if(!isConnected)
				return;
			Main.app.track("/burnFW");
			Main.app.scriptsPart.clearInfo();

			var boards:Array = Main.app.extensionManager.extensionByName().boardType.split(":");
			if(boards[1] == "samd") {
				_serial.close();
				_serial.open(selectPort,1200);
			//	var start:uint = getTimer();
			//	while(getTimer() - start < 100){}
				_serial.close();

				setTimeout(_burnFW2, 3000, hexFile);
				_dialog.setText(Translator.map('Executing'));
				_dialog.showOnStage(_mBlock.stage);
			} else {
				_burnFW2(hexFile);
			}
		}

		private function _burnFW2(hexFile:String):void
		{
			Main.app.track("/burnFW2");

			var boards:Array = Main.app.extensionManager.extensionByName().boardType.split(":");

			var partFile:String = hexFile+".ino.partitions.bin";
			hexFile = hexFile+".ino"+ArduinoManager.sharedManager().getHexFilename(boards);
			if(!File.applicationDirectory.resolvePath(hexFile).exists){
				Main.app.track("upgrade fail!");
				return;
			}

			var hardwareDir:String;
			var extStr:String = "";
			if(ApplicationManager.sharedManager().system == ApplicationManager.MAC_OS) {
				hardwareDir = "Arduino/Arduino.app/Contents/Java";
			} else {
				hardwareDir = "Arduino";
				extStr = ".exe";
			}
			hardwareDir = File.applicationDirectory.resolvePath(hardwareDir).nativePath;

			var cmd:String;
			var args:String;
			switch(boards[1]) {
			case "avr":
			default:
				args = "-C"+hardwareDir+"/hardware/tools/avr/etc/avrdude.conf -v -patmega328p -carduino -P"+selectPort+" -b115200 -D -V"
					+" -Uflash:w:"+File.applicationDirectory.resolvePath(hexFile).nativePath+":i";
				cmd = hardwareDir+"/hardware/tools/avr/bin/avrdude"+extStr;
				break;

			case "samd":	// board=mzero_bl
				var list:Array = this.portlist;
				if(list.length == 0) {
					Main.app.track("upgrade fail!");
					return;
				}
				var burnPort:String = list[list.length-1];
				Main.app.track(selectPort+"->"+burnPort);
				Main.app.scriptsPart.appendMessage(selectPort+"->"+burnPort);

				args = "-C"+hardwareDir+"/hardware/tools/avr/etc/avrdude.conf -v -patmega2560 -cstk500v2 -P"+burnPort+" -b57600"
					+" -Uflash:w:"+File.applicationDirectory.resolvePath(hexFile).nativePath+":i";
				cmd = hardwareDir+"/hardware/tools/avr/bin/avrdude"+extStr;
				break;

			case "esp32":
				cmd = "Arduino/portable/packages/esp32/tools/esptool_py/2.6.1/esptool.exe";
				cmd = File.applicationDirectory.resolvePath(cmd).nativePath;

				args = "--chip esp32 --port "+selectPort+" --baud 921600 --before default_reset --after hard_reset write_flash -z --flash_mode dio --flash_freq 80m --flash_size detect"
					+" 0xe000 Arduino/portable/packages/esp32/hardware/esp32/1.0.4/tools/partitions/boot_app0.bin"
					+" 0x1000 Arduino/portable/packages/esp32/hardware/esp32/1.0.4/tools/sdk/bin/bootloader_qio_80m.bin"
					+" 0x10000 "+File.applicationDirectory.resolvePath(hexFile).nativePath
					+" 0x8000 "+File.applicationDirectory.resolvePath(partFile).nativePath;
				break;
			}

			if(!File.applicationDirectory.resolvePath(cmd).exists){
				Main.app.track("upgrade fail!");
				return;
			}

			_dialog.setText(Translator.map('Executing'));
			_dialog.showOnStage(_mBlock.stage);

			Main.app.topBarPart.setConnectedButton(false);
			ArduinoManager.sharedManager().isUploading = false;
			_serial.close();

			upgradeFirmware(cmd, args);
		}

		private function upgradeFirmware(cmd:String, args:String):void
		{
			Main.app.scriptsPart.appendMessage(cmd + " " + args);

			var info:NativeProcessStartupInfo =new NativeProcessStartupInfo();
			info.executable = File.applicationDirectory.resolvePath(cmd);
			info.arguments = Vector.<String>(args.split(" "));

			var process:NativeProcess = new NativeProcess();
			process.addEventListener(ProgressEvent.STANDARD_OUTPUT_DATA,onStandardOutputData);
			process.addEventListener(ProgressEvent.STANDARD_ERROR_DATA, onErrorData);
			process.addEventListener(NativeProcessExitEvent.EXIT, onExit);
			process.start(info);
			ArduinoManager.sharedManager().isUploading = true;
		}
		
		private function onStandardOutputData(event:ProgressEvent):void
		{
			var process:NativeProcess = event.target as NativeProcess;
			Main.app.scriptsPart.appendRawMessage(process.standardOutput.readUTFBytes(process.standardOutput.bytesAvailable));
			_dialog.setText(Translator.map('Uploading') + " ... " + "0%");
		}

		private function onErrorData(event:ProgressEvent):void
		{
			var process:NativeProcess = event.target as NativeProcess;
			Main.app.scriptsPart.appendRawMessage(process.standardError.readUTFBytes(process.standardError.bytesAvailable));
			_dialog.setText(Translator.map('Uploading') + " ... " + "0%");
		}
		
		private function onExit(event:NativeProcessExitEvent):void
		{
			ArduinoManager.sharedManager().isUploading = false;
			Main.app.track("Process exited with "+event.exitCode);
			if(event.exitCode > 0){
				_dialog.setText(Translator.map('Upload Failed'));
			}else{
				_dialog.setText(Translator.map('Upload Finish'));
			}
			setTimeout(onOpen, 2000, selectPort);
			//setTimeout(_dialog.cancel,2000);
		}
	}
}