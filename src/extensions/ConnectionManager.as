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
	import cc.makeblock.mbot.util.AppTitleMgr;
//	import cc.makeblock.util.UploadSizeInfo;
	
	import translation.Translator;
	
	import uiwidgets.DialogBox;
	
	import util.ApplicationManager;

	import blockly.signals.Signal;

	public class ConnectionManager extends EventDispatcher
	{
		private static var _instance:ConnectionManager;
		private var _serial:AIRSerial;
	//	public var extensionName:String = "";

		public var selectPort:String = "";		// 選択中の "COMx"
		private var _receiveHandler:Function=null;

		private var _mBlock:Main;
		private var _upgradeBytesTotal:Number = 0;
		private var _dialog:DialogBox = new DialogBox();
		private var _hexToDownload:String = ""
			
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
		}
		private function onTimerCheck(evt:TimerEvent):void{
			if(_serial.isConnected){
				if(this.portlist.indexOf(selectPort) == -1){
					onClose();
				}
			}
		}
		public function setMain(mBlock:Main):void{
			_mBlock = mBlock;
		}

		// list

		public function get portlist():Array{
			var _currentList:Array = [];	// portlist, 
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

		// 0. 									- addEventListener(Event.CONNECT, onConnected)
		// 1. onConnect("serial_COM3")			- setTimeout(onOpen, 100, "COM3")
		// 2. onOpen("COM3)						- Event.CONNECT
		// 3. onConnected (JavaScriptEngine.as)
		// 4. _deviceConnected (robot.js)
		// 5. open(115200, deviceOpened)
		// 6. deviceOpened (robot.js)			- set_receive_handler(processData)

		public function onConnect(name:String):void{
			switch(name){
				case "upgrade_firmware":{
					upgrade(File.applicationDirectory.nativePath + "/ext/firmware/hex/robot_pcmode/robot_pcmode.cpp.standard.hex");
					break;
				}
				case "reset_program":{
					upgrade(File.applicationDirectory.nativePath + "/ext/firmware/hex/robot_normal/robot_normal.cpp.standard.hex");
					break;
				}
				default:{
					BlockInterpreter.Instance.stopAllThreads();
					if(name.indexOf("serial_")>-1){
						var port:String = name.split("serial_").join("");

						if(selectPort==port && _serial.isConnected){
							onClose();
						}else{
							if(_serial.isConnected){
								onClose();
							}
							setTimeout(onOpen, 100, port);
						}
					}
				}
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
				Main.app.topBarPart.setConnectedTitle("Connect");
				openedHandle(this);
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
			if(selectPort != ""){
				this.dispatchEvent(new Event(Event.CONNECT));
			}
		}

		public function update():void{
			if(!_serial.isConnected){
				Main.app.topBarPart.setDisconnectedTitle();
				return;
			}else{
				Main.app.topBarPart.setConnectedTitle("Connect");
			}
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
				Main.app.topBarPart.setDisconnectedTitle();
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
		// 2. _onReceived					- _receiveHandler(_receivedBytes)
		// 3. processData (robot.js)	

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

	//	public const dataRecvSignal:Signal = new Signal(Array);
		private function _onReceived(evt:Event):void
		{
			var _receivedBytes:Array = [];
			_bytes.position=0;
			while(_bytes.bytesAvailable > 0){
				_receivedBytes.push(_bytes.readUnsignedByte());
			}
			_bytes.clear();

			if(_receivedBytes.length > 0){
	//			dataRecvSignal.notify(_receivedBytes);		// RemoteCallMgr
			}
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

		// update

		private var _isInitUpgrade:Boolean = false;
		private function upgrade(hexFile:String=""):void{
			if(!isConnected){
				return;
			}
			Main.app.track("/OpenSerial/Upgrade");

			if(!_isInitUpgrade){
				_isInitUpgrade = true;
				function cancel():void { _dialog.cancel(); }
				_dialog.addTitle(Translator.map('Start Uploading'));
				_dialog.addButton(Translator.map('Close'), cancel);
			}else{
				_dialog.setTitle(('Start Uploading'));
				_dialog.setButton(('Close'));
			}
			_dialog.setText(Translator.map('Executing'));
			_dialog.showOnStage(_mBlock.stage);

			_hexToDownload = hexFile;
			Main.app.topBarPart.setConnectedTitle(AppTitleMgr.Uploading);
			ArduinoManager.sharedManager().isUploading = false;
			_serial.close();
			upgradeFirmware();
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
		private var process:NativeProcess;
		static private function getAvrDude():File
		{
			if(ApplicationManager.sharedManager().system == ApplicationManager.MAC_OS){
				return File.applicationDirectory.resolvePath("Arduino/Arduino.app/Contents/Java/hardware/tools/avr/bin/avrdude");
			}
			return File.applicationDirectory.resolvePath("Arduino/hardware/tools/avr/bin/avrdude.exe");
		}
		
		static private function getAvrDudeConfig():File
		{
			if(ApplicationManager.sharedManager().system == ApplicationManager.MAC_OS){
				return File.applicationDirectory.resolvePath("Arduino/Arduino.app/Contents/Java/hardware/tools/avr/etc/avrdude.conf");
			}
			return File.applicationDirectory.resolvePath("Arduino/hardware/tools/avr/etc/avrdude.conf");
		}
		
		private function upgradeFirmware(hexfile:String=""):void{
			var file:File = getAvrDude();//外部程序名
			if(!file.exists){
				Main.app.track("upgrade fail!");
				return;
			}
			Main.app.topBarPart.setConnectedTitle(AppTitleMgr.Uploading);
			var tf:File;
		//	var currentDevice:String = DeviceManager.sharedManager().currentDevice;
			var nativeProcessStartupInfo:NativeProcessStartupInfo =new NativeProcessStartupInfo();
			nativeProcessStartupInfo.executable = file;
			var v:Vector.<String> = new Vector.<String>();//外部应用程序需要的参数
			v.push("-C");
			v.push(getAvrDudeConfig().nativePath)
			v.push("-v");
			v.push("-v");
			v.push("-v");
			v.push("-v");
			v.push("-patmega328p");
			v.push("-carduino"); 
			v.push("-P"+selectPort); //this.port);
			v.push("-b115200");
			v.push("-D");
			v.push("-V");
			v.push("-U");
			v.push("flash:w:"+_hexToDownload+":i");
			tf = new File(_hexToDownload);
			if(tf!=null && tf.exists){
				_upgradeBytesTotal = tf.size;
//				Main.app.track("total:",_upgradeBytesTotal);
			}else{
				_upgradeBytesTotal = 0;
			}
			nativeProcessStartupInfo.arguments = v;
			process = new NativeProcess();
			process.addEventListener(ProgressEvent.STANDARD_OUTPUT_DATA,onStandardOutputData);
			process.addEventListener(ProgressEvent.STANDARD_ERROR_DATA, onErrorData);
			process.addEventListener(NativeProcessExitEvent.EXIT, onExit);
//			process.addEventListener(IOErrorEvent.STANDARD_OUTPUT_IO_ERROR, onIOError);
//			process.addEventListener(IOErrorEvent.STANDARD_ERROR_IO_ERROR, onIOError);
			process.start(nativeProcessStartupInfo);
//			sizeInfo.reset();
			Main.app.scriptsPart.clearInfo();
			Main.app.scriptsPart.appendMessage(nativeProcessStartupInfo.executable.nativePath + " " + v.join(" "));
			ArduinoManager.sharedManager().isUploading = true;
			
		}
		
		private var errorText:String;
//		private var sizeInfo:UploadSizeInfo = new UploadSizeInfo();
		private function onStandardOutputData(event:ProgressEvent):void
		{
			var msg:String = process.standardError.readUTFBytes(process.standardError.bytesAvailable);
			Main.app.scriptsPart.appendRawMessage(msg);
		}
		private function onErrorData(event:ProgressEvent):void
		{
			var msg:String = process.standardError.readUTFBytes(process.standardError.bytesAvailable);
			if(null == errorText){
				errorText = msg;
			}else{
				errorText += msg;
			}
			Main.app.scriptsPart.appendRawMessage(msg);
			_dialog.setText(Translator.map('Uploading') + " ... " + "0%");// + sizeInfo.update(msg) + "%");
		}
		
		private function onExit(event:NativeProcessExitEvent):void
		{
			ArduinoManager.sharedManager().isUploading = false;
			Main.app.track("Process exited with "+event.exitCode);
			if(event.exitCode > 0){
				_dialog.setText(Translator.map('Upload Failed'));
				Main.app.track(errorText);
				Main.app.scriptsPart.appendMsgWithTimestamp(errorText, true);
			}else{
				_dialog.setText(Translator.map('Upload Finish'));
			}
			setTimeout(onOpen, 2000, selectPort);
			errorText = null;
			//setTimeout(_dialog.cancel,2000);
		}
	/*
		public function reopen():void
		{
			_open(selectPort);
		}
	*/
	}
}