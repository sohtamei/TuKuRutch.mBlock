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
	import flash.utils.getTimer;
	import flash.utils.setTimeout;
	import cc.makeblock.interpreter.BlockInterpreter;
	import cc.makeblock.mbot.util.AppTitleMgr;
	import cc.makeblock.util.UploadSizeInfo;
	
	import translation.Translator;
	
	import uiwidgets.DialogBox;
	
	import util.ApplicationManager;
//	import util.SharedObjectManager;

	public class SerialManager extends EventDispatcher
	{
		private var moduleList:Array = [];
		private var _currentList:Array = [];
		private static var _instance:SerialManager;
		public var currentPort:String = "";
		private var _selectPort:String = "";
		public var _mBlock:MBlock;
//		private var _board:String = "uno";
//		private var _device:String = "uno";
//		private var _upgradeBytesLoaded:Number = 0;
		private var _upgradeBytesTotal:Number = 0;
		private var _isInitUpgrade:Boolean = false;
		private var _dialog:DialogBox = new DialogBox();
		private var _hexToDownload:String = ""
			
//		private var _isMacOs:Boolean = ApplicationManager.sharedManager().system==ApplicationManager.MAC_OS;
//		private var _avrdude:String = "";
//		private var _avrdudeConfig:String = "";
		public static function sharedManager():SerialManager{
			if(_instance==null){
				_instance = new SerialManager;
			}
			return _instance;
		}
		private var _serial:AIRSerial;
		
		public function SerialManager()
		{
			_serial = new AIRSerial();
//			_avrdude = _isMacOs?"avrdude":"avrdude.exe";
//			_avrdudeConfig = _isMacOs?"avrdude_mac.conf":"avrdude.conf";
			
//			_board = SharedObjectManager.sharedManager().getObject("board","uno");
//			_device = SharedObjectManager.sharedManager().getObject("device","uno");
			var timer:Timer = new Timer(4000);
			timer.addEventListener(TimerEvent.TIMER,onTimerCheck);
			timer.start();
		}
		private function onTimerCheck(evt:TimerEvent):void{
			if(_serial.isConnected){
				if(this.list.indexOf(_selectPort)==-1){
					this.close();
				}
			}
		}
		public function setMBlock(mBlock:MBlock):void{
			_mBlock = mBlock;
		}
		public var asciiString:String = "";
		private function onChanged(evt:Event):void{
			var len:uint = _serial.getAvailable();
			if(len>0){
				ConnectionManager.sharedManager().onReceived(_serial.readBytes());
			}
			return;
/*
			if(len>0){
				var bytes:ByteArray = _serial.readBytes();
				bytes.position = 0;
				asciiString = "";
				var hasNonChar:Boolean = false;
				var c:uint;
				for(var i:uint=0;i<bytes.length;i++){
					c = bytes.readByte();
					asciiString += String.fromCharCode();
					if(c<30){
						hasNonChar = true;
					}
				}
				if(!hasNonChar)dispatchEvent(new Event(Event.CHANGE));
				bytes.position = 0;
				ParseManager.sharedManager().parseBuffer(bytes);
			}
*/
		}
		public function get isConnected():Boolean{
			return _serial.isConnected;
		}
		public function get list():Array{
			try{
				_currentList = formatArray(_serial.list().split(",").sort());
				var emptyIndex:int = _currentList.indexOf("");
				if(emptyIndex>-1){
					_currentList.splice(emptyIndex,emptyIndex+1);
				}
			}catch(e:*){
				
			}
			return _currentList;
		}
		private function formatArray(arr:Array):Array {
			var obj:Object={};
			return arr.filter(function(item:*, index:int, array:Array):Boolean{
				return !obj[item]?obj[item]=true:false
			});
		}
		public function update():void{
			if(!_serial.isConnected){
				MBlock.app.topBarPart.setDisconnectedTitle();
				return;
			}else{
				MBlock.app.topBarPart.setConnectedTitle("Connect");
			}
		}
		
		public function sendBytes(bytes:ByteArray):void{
			if(_serial.isConnected){
				_serial.writeBytes(bytes);
			}
		}
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
		public function open(port:String,baud:uint=115200):Boolean{
			if(_serial.isConnected){
				_serial.close();
			}
			_serial.addEventListener(Event.CHANGE,onChanged);
			var r:uint = _serial.open(port,baud);
			_selectPort = port;
			ArduinoManager.sharedManager().isUploading = false;
			if(r==0){
				MBlock.app.topBarPart.setConnectedTitle("Connect");
			}
			return r == 0;
		}
		public function close():void{
			if(_serial.isConnected){
				SerialDevice.sharedDevice().clearAll();
				BlockInterpreter.Instance.stopAllThreads();
				_serial.removeEventListener(Event.CHANGE,onChanged);
				_serial.close();
				ConnectionManager.sharedManager().onClose(_selectPort);
			}
		}
		public function connect(port:String):int{
			if(SerialDevice.sharedDevice().ports.indexOf(port)>-1&&_serial.isConnected){
				close();
			}else{
				if(_serial.isConnected){
					close();
				}
				setTimeout(ConnectionManager.sharedManager().onOpen,100,port);
			}
			return 0;
		}
		public function upgrade(hexFile:String=""):void{
			if(!isConnected){
				return;
			}
			MBlock.app.track("/OpenSerial/Upgrade");
			executeUpgrade();
			_hexToDownload = hexFile;
			MBlock.app.topBarPart.setConnectedTitle(AppTitleMgr.Uploading);
			ArduinoManager.sharedManager().isUploading = false;
			_serial.close();
			upgradeFirmware();
			currentPort = "";
		}
		public function disconnect():void{
			currentPort = "";
			MBlock.app.topBarPart.setDisconnectedTitle();
//			MBlock.app.topBarPart.setBluetoothTitle(false);
			ArduinoManager.sharedManager().isUploading = false;
			_serial.close();
			_serial.removeEventListener(Event.CHANGE,onChanged);
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
		
		public function upgradeFirmware(hexfile:String=""):void{
			var file:File = getAvrDude();//外部程序名
			if(!file.exists){
				MBlock.app.track("upgrade fail!");
				return;
			}
			MBlock.app.topBarPart.setConnectedTitle(AppTitleMgr.Uploading);
			var tf:File;
			var currentDevice:String = DeviceManager.sharedManager().currentDevice;
			currentPort = SerialDevice.sharedDevice().port;
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
			v.push("-P"+currentPort);
			v.push("-b115200");
			v.push("-D");
			v.push("-V");
			v.push("-U");
			v.push("flash:w:"+_hexToDownload+":i");
			tf = new File(_hexToDownload);
			if(tf!=null && tf.exists){
				_upgradeBytesTotal = tf.size;
//				MBlock.app.track("total:",_upgradeBytesTotal);
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
			sizeInfo.reset();
			MBlock.app.scriptsPart.clearInfo();
			MBlock.app.scriptsPart.appendMessage(nativeProcessStartupInfo.executable.nativePath + " " + v.join(" "));
			ArduinoManager.sharedManager().isUploading = true;
			
		}
		
		private var errorText:String;
		private var sizeInfo:UploadSizeInfo = new UploadSizeInfo();
		private function onStandardOutputData(event:ProgressEvent):void
		{
			var msg:String = process.standardError.readUTFBytes(process.standardError.bytesAvailable);
			MBlock.app.scriptsPart.appendRawMessage(msg);
		}
		private function onErrorData(event:ProgressEvent):void
		{
			var msg:String = process.standardError.readUTFBytes(process.standardError.bytesAvailable);
			if(null == errorText){
				errorText = msg;
			}else{
				errorText += msg;
			}
			MBlock.app.scriptsPart.appendRawMessage(msg);
			_dialog.setText(Translator.map('Uploading') + " ... " + sizeInfo.update(msg) + "%");
		}
		
		private function onExit(event:NativeProcessExitEvent):void
		{
			ArduinoManager.sharedManager().isUploading = false;
			MBlock.app.track("Process exited with "+event.exitCode);
			if(event.exitCode > 0){
				_dialog.setText(Translator.map('Upload Failed'));
				MBlock.app.track(errorText);
				MBlock.app.scriptsPart.appendMsgWithTimestamp(errorText, true);
			}else{
				_dialog.setText(Translator.map('Upload Finish'));
			}
			setTimeout(open,2000,_selectPort);
			errorText = null;
			//setTimeout(_dialog.cancel,2000);
		}
		public function executeUpgrade():void {
			if(!_isInitUpgrade){
				_isInitUpgrade = true;
				function cancel():void { _dialog.cancel(); }
				_dialog.addTitle(Translator.map('Start Uploading'));
				_dialog.addButton(Translator.map('Close'), cancel);
			}else{
				_dialog.setTitle(('Start Uploading'));
				_dialog.setButton(('Close'));
			}
		//	_upgradeBytesLoaded = 0;
			_dialog.setText(Translator.map('Executing'));
			_dialog.showOnStage(_mBlock.stage);
		}
		
		public function reopen():void
		{
			open(_selectPort);
		}
	}
}