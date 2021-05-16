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

	import flash.events.DatagramSocketDataEvent;
	import flash.events.IOErrorEvent;
	import flash.events.SecurityErrorEvent;
	import flash.net.DatagramSocket;
	import flash.net.Socket;
	import flash.utils.getTimer;

	public class ConnectionManager extends EventDispatcher
	{
		private static var _instance:ConnectionManager;
		private var _serial:AIRSerial;

		public var selectPort:String = "";		// 選択中の "COMx"
		private var _receiveHandler:Function=null;

		private var _mBlock:Main;
		private var _dialog:DialogBox;
			
//		private var _isMacOs:Boolean = ApplicationManager.sharedManager().system==ApplicationManager.MAC_OS;
//		private var _avrdude:String = "";
//		private var _avrdudeConfig:String = "";

		private var _clientPort:int = 54321;
		private var datagramSocket:DatagramSocket;
		public var socketList:Array = [];
		private var _socket:Socket = new Socket();

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
			
			// udp port
			datagramSocket = new DatagramSocket();
			datagramSocket.addEventListener(DatagramSocketDataEvent.DATA, datagramReceived);
			try{
				datagramSocket.bind(_clientPort);
				datagramSocket.receive();
			}catch(e:*){
				
			}
		}

		private function onTimerCheck(evt:TimerEvent):void{
			var arr:Array = portlist;
			if(_serial.isConnected && arr.indexOf(selectPort) == -1) {
				onClose();
				return;
			}
			
			var i:int;
			for(i=0; i<socketList.length; i++) {
				if(!socketList[i].updated) {
					var address:String = socketList[i].address;
					socketList.removeAt(i);
					if(_socket.connected && selectPort == address) {
						onClose();
						return;
					}
				}
			}
			update();
			for(i=0; i<socketList.length; i++) {
				if(socketList[i].name != "custom")
					socketList[i].updated = false;
			}
		}

		public function setMain(mBlock:Main):void{
			_mBlock = mBlock;
		}

		// list

		public function get portlist():Array{
			// "COM3,COM1,COM2,COM2,COM1," ソート、重複削除、NULL削除
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

		// 0. JavaScriptEngine/loadJS		- addEventListener(Event.CONNECT(this), onConnected)
		// -- USB uart --
		// 1. toggle("COM3")
		// -- net --
		// 1. toggle("192.168.1.45")		- Event.CONNECT(socket)
		// -- common --
		// 2. connectHandler				- Event.CONNECT(this)
		// 3. JavaScriptEngine/onConnected
		// 4. _deviceConnected (robot.js, checkDevName)	- set_receive_handler(processData)

		public function toggle(port:String):void{
			BlockInterpreter.Instance.stopAllThreads();
			if(_serial.isConnected||_socket.connected) {
				if(selectPort==port) {
					onClose();
					return;
				} else {
					_close();
				}
			}

			selectPort = port;
			if(port.indexOf("COM")>=0||port.indexOf("/dev/tty.")>=0){
			// USB uart
				if(_serial.isConnected) _serial.close();
				_serial.removeEventListener(Event.CHANGE, onChanged);
				_serial.addEventListener(Event.CHANGE, onChanged);

				var boards:Array = Main.app.extensionManager.extensionByName().boardType.split(":");
				_serial.open(selectPort, (boards[1]=="nRF5")?19200:115200);
				connectHandler();
			} else {
			// wifi
				if(port.length>6 && port.split(".").length>3){
					configureListeners(_socket);
					try{
						_socket.connect(port, _clientPort);
					}catch(e:Error){
						trace(e);
					}
				}
			}
		}

		private function configureListeners(socket:Socket):void {
			socket.removeEventListener(Event.CLOSE, _closeHandler);
			socket.removeEventListener(Event.CONNECT, connectHandler);
			socket.removeEventListener(IOErrorEvent.IO_ERROR, _ioErrorHandler);
			socket.removeEventListener(SecurityErrorEvent.SECURITY_ERROR, _securityErrorHandler);
			socket.removeEventListener(ProgressEvent.SOCKET_DATA, socketDataHandler);
			socket.addEventListener(Event.CLOSE, _closeHandler);
			socket.addEventListener(Event.CONNECT, connectHandler);
			socket.addEventListener(IOErrorEvent.IO_ERROR, _ioErrorHandler);
			socket.addEventListener(SecurityErrorEvent.SECURITY_ERROR, _securityErrorHandler);
			socket.addEventListener(ProgressEvent.SOCKET_DATA, socketDataHandler);

			function _closeHandler(evt:Event):void {
				Main.app.track("closeHandler: " + evt);
				_close();
			}

			function _ioErrorHandler(evt:IOErrorEvent):void {
				trace("ioErrorHandler: " + evt);
			}
			
			function _securityErrorHandler(event:SecurityErrorEvent):void {
				trace("securityErrorHandler: " + event);
			}
		}

		public var checkDevName:Boolean = true;
		private function connectHandler(evt:Event=null):void {
			Main.app.track("connection:"+selectPort);
			update();
			ArduinoManager.sharedManager().isUploading = false;

			checkDevName = true;
			var boards:Array = Main.app.extensionManager.extensionByName().boardType.split(":");
			switch(boards[1]) {
			case "samd":
			case "esp32":
				checkDevName = false;
				break;
			}
			removeEventListener(Event.CHANGE,_onReceived);
			addEventListener(Event.CHANGE,_onReceived);

			this.dispatchEvent(new Event(Event.CONNECT));
		}

		public function set_receive_handler(receiveHandler:Function):void{
			_receiveHandler = receiveHandler;
		}

		public function connected(port:String=null):Boolean{
			return (_serial.isConnected||_socket.connected) && port==selectPort;
		}

		public function get isConnected():Boolean{
			return (_serial.isConnected||_socket.connected);
		}

		public function get isConnectedUart():Boolean{
			return (_serial.isConnected);
		}

		public function onRemoved(extName:String = ""):void{
			this.dispatchEvent(new Event(Event.REMOVED));
		}

		public function onReOpen():void{
			if(selectPort != "")
				this.dispatchEvent(new Event(Event.CONNECT));
		}

		public function update():void{
			Main.app.topBarPart.setConnectedButton(
				_serial.isConnected ? 2: (portlist.length ? 1:0),
				_socket.connected   ? 2: (socketList.length ? 1:0));
		}

		// close

		// 1. onClose						- Event.CLOSE(this)
		// 2. JavaScriptEngine/onClosed
		// 3. robot.js/_deviceRemoved

		public function onClose():void{
			this.dispatchEvent(new Event(Event.CLOSE));		// send "reset"(samd,esp32)
			if(checkDevName) {
				_close();
			} else {
				setTimeout(_close, 500);
			}
		}

		private function _close():void{
			BlockInterpreter.Instance.stopAllThreads();
			ArduinoManager.sharedManager().isUploading = false;
			_receiveHandler = null;
			if(_serial.isConnected){
				_serial.close();
			}
			if(_socket.connected){
				try{
					_socket.close();
				}catch(e:Error){
					trace(e);
				}
			}
			update();
		}

		// recv

		// -- USB uart --
		// 0.								- Event.CHANGE (_serial)
		// 1. onChanged						- Event.CHANGE (this)
		// -- net --
		// 0.								- ProgressEvent.SOCKET_DATA (socket)
		// 1. socketDataHandler				- Event.CHANGE (this)
		// -- common --
		// 2. _onReceived					- _receiveHandler = processData(_receivedBytes)
		// 3. robot.js/processData			- JavaScriptEngine/responseValue - RemoteCallMgr/onPacketRecv - thread.push&thread.resume

		private var _bytes:ByteArray = new ByteArray();
		private function onChanged(evt:Event):void{
			var len:uint = _serial.getAvailable();
			if(len>0){
				_bytes = _serial.readBytes();
				Main.app.scriptsPart.onSerialDataReceived(_bytes);	// debug
				this.dispatchEvent(new Event(Event.CHANGE));
			}
			return;
		}

		private function socketDataHandler(evt:ProgressEvent):void {
			var socket:Socket = evt.target as Socket;
			socket.readBytes(_bytes);
			Main.app.scriptsPart.onSerialDataReceived(_bytes);	// debug
			this.dispatchEvent(new Event(Event.CHANGE));
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
		private var _prevTime:Number = 0;
		public function sendBytes(bytes:ByteArray):void{
			if(_serial.isConnected){
				_serial.writeBytes(bytes);
			} else if(_socket.connected){
			//	var cTime:Number = getTimer();
			//	if(cTime-_prevTime>20){
			//		_prevTime = cTime; 
					_socket.writeBytes(bytes);
					_socket.flush();
			//	}
			}
			bytes.clear();
		}

		// update

		public function burnFW(hexFile:String):void
		{
			if(!_serial.isConnected) return;	// debug
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
				_dialog = new DialogBox();
				_dialog.addTitle(Translator.map('Start Uploading'));
			//	_dialog.addButton(Translator.map('Close'), null);
				_dialog.setText(Translator.map('Executing'));
				_dialog.showOnStage(_mBlock.stage);
			} else {
				_burnFW2(hexFile);
			}
		}

		private function _burnFW2(hexFile:String):void
		{
			Main.app.track("/burnFW2");

			var ext:ScratchExtension = Main.app.extensionManager.extensionByName();
			var boards:Array = ext.boardType.split(":");

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
				var list:Array = portlist;
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

				var baud:String = "921600";
				for each(var pref:String in ext.prefs) {
					if(pref.indexOf("custom_UploadSpeed=")>=0) {
						pref = pref.substr("custom_UploadSpeed=".length);
						var pos:int = pref.indexOf("_");
						if(pos > 0) baud = pref.substr(pos+1);
						break;
					}
				}
				
				args = "--chip esp32 --port "+selectPort+" --baud "+baud+" --before default_reset --after hard_reset write_flash -z --flash_mode dio --flash_freq 80m --flash_size detect"
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

			_dialog = new DialogBox();
			_dialog.addTitle(Translator.map('Start Uploading'));
		//	_dialog.addButton(Translator.map('Close'), null);
			_dialog.setText(Translator.map('Executing'));
			_dialog.showOnStage(_mBlock.stage);

			_serial.close();
			update();
			ArduinoManager.sharedManager().isUploading = false;

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

			function onStandardOutputData(event:ProgressEvent):void
			{
				var process:NativeProcess = event.target as NativeProcess;
				Main.app.scriptsPart.appendRawMessage(process.standardOutput.readUTFBytes(process.standardOutput.bytesAvailable));
				_dialog.setText(Translator.map('Uploading') + " ... " + "0%");
			}

			function onErrorData(event:ProgressEvent):void
			{
				var process:NativeProcess = event.target as NativeProcess;
				Main.app.scriptsPart.appendRawMessage(process.standardError.readUTFBytes(process.standardError.bytesAvailable));
				_dialog.setText(Translator.map('Uploading') + " ... " + "0%");
			}
			
			function onExit(event:NativeProcessExitEvent):void
			{
				ArduinoManager.sharedManager().isUploading = false;
				Main.app.track("Process exited with "+event.exitCode);
				_dialog.addButton(Translator.map('Close'), null);
				if(event.exitCode > 0){
					_dialog.setText(Translator.map('Upload Failed'));
				}else{
					_dialog.setText(Translator.map('Upload Finish'));
				}
				setTimeout(toggle, 2000, selectPort);
				//setTimeout(_dialog.cancel,2000);
			}
		}
		
		// SocketManager
		
		private function datagramReceived(evt:DatagramSocketDataEvent):void 
		{
			var srcName:String = evt.data.readUTFBytes(evt.data.bytesAvailable);
			if(srcName.length<=0) return;
			addSockets(evt.srcAddress, srcName);
		}

		public function addSockets(address:String, name:String):void
		{
			for each(var dev:Object in socketList) {
				if(dev.address == address) {
					dev.updated = true;
					return;
				}
			}

			var temp:Object = {address:address, name:name, updated:true};
			socketList.push(temp);
			Main.app.track("Received from " + address);
			update();
		}
	}

}

