// remoconRobo.js

(function(ext) {
	var device = null;
	var _rxBuf = [];

	var levels = {"HIGH":1,"LOW":0};
	var onoff = {"On":1,"Off":0};
	var directions = {"run forward":0,"turn left":1,"turn right":2,"run backward":3,"rotate left":4,"rotate right":5};
	var tones ={"C2":65,"D2":73,"E2":82,"F2":87,"G2":98,"A2":110,"B2":123,
				"C3":131,"D3":147,"E3":165,"F3":175,"G3":196,"A3":220,"B3":247,
				"C4":262,"D4":294,"E4":330,"F4":349,"G4":392,"A4":440,"B4":494,
				"C5":523,"D5":587,"E5":659,"F5":698,"G5":784,"A5":880,"B5":988,
				"C6":1047,"D6":1175,"E6":1319,"F6":1397,"G6":1568,"A6":1760,"B6":1976,
				"C7":2093,"D7":2349,"E7":2637,"F7":2794,"G7":3136,"A7":3520,"B7":3951,
				"C8":4186,"D8":4699,
				"ド2":65,"レ2":73,"ミ2":82,"ファ2":87,"ソ2":98,"ラ2":110,"シ2":123,
				"ド3":131,"レ3":147,"ミ3":165,"ファ3":175,"ソ3":196,"ラ3":220,"シ3":247,
				"ド4":262,"レ4":294,"ミ4":330,"ファ4":349,"ソ4":392,"ラ4":440,"シ4":494,
				"ド5":523,"レ5":587,"ミ5":659,"ファ5":698,"ソ5":784,"ラ5":880,"シ5":988,
				"ド6":1047,"レ6":1175,"ミ6":1319,"ファ6":1397,"ソ6":1568,"ラ6":1760,"シ6":1976,
				"ド7":2093,"レ7":2349,"ミ7":2637,"ファ7":2794,"ソ7":3136,"ラ7":3520,"シ7":3951,
				"ド8":4186,"レ8":4699};
	var beats = {"Half":500,"Quarter":250,"Eighth":125,"Whole":1000,"Double":2000,"Zero":0};
//	var ircodes = {	"A":0x45,"B":0x46,"C":0x47,"D":0x44,"E":0x43,"R0":0x16,"F":0x0D,"↑":0x40,"↓":0x19,"←":0x07,"→":0x09,"CENTER":0x15,
	var ircodes = {	"POWER":0x45,"B":0x46,"MENU":0x47,"TEST":0x44,"RETURN":0x43,"R0":0x16,"C":0x0D,"↑":0x40,"↓":0x19,"←":0x07,"→":0x09,"CENTER":0x15,
					"R1":0x0C,"R2":0x18,"R3":0x5E,"R4":0x08,"R5":0x1C,"R6":0x5A,"R7":0x42,"R8":0x52,"R9":0x4A,
					"A CENTER":0x61,"A↑":0x62,"A→":0x63,"A←":0x64,"A↓":0x65};
	var remoteKey = 0;
	var remoteX = 0;
	var remoteY = 0;
	ext.resetAll = function(){
		device.send([0xff, 0x55, 2, 0, 4]);
	};
	ext.runArduino = function(){
		responseValue();
	};
	
	ext.runRobot = function(direction,speed) {
		if(typeof direction == "string"){
			direction = directions[direction];
		}
		runPackage(5,direction,speed);
	};
	ext.stopRobot= function() {
		runPackage(5,0,0);
	}
	ext.runMotor = function(port,speed) {
		runPackage(10,port,short2array(speed));
	};

	ext.runCalibRight = function(inc) {
		runPackage(39,short2array(inc));
	};
	ext.runCalibLeft = function(inc) {
		runPackage(39,short2array(-inc));
	};
	ext.getCalib = function() {
		getPackage(37);
	};
	ext.runSetCalib = function(calib) {
		runPackage(38,short2array(calib));
	};

	ext.runDigital = function(pin,level) {
		runPackage(30,pin,typeof level == "string"?levels[level]:new Number(level));
	};
	ext.runDigitalA = function(pin,level) {
		runPackage(30,14+pin,typeof level == "string"?levels[level]:new Number(level));
	};
	ext.runServoArduino = function(pin, angle){
		runPackage(33,pin,angle);
	};
	ext.runLED = function(level) {
		runPackage(30,13,typeof level == "string"?onoff[level]:new Number(level));
	};
	ext.runBuzzer = function(tone, beat){
		if(typeof tone == "string"){
			tone = tones[tone];
		}
		if(typeof beat == "string"){
			beat = parseInt(beat) || beats[beat];
		}
		runPackage(34,short2array(tone), short2array(beat));
	};
	ext.runBuzzerJ1 = function(tone, beat){
		ext.runBuzzer(tone, beat);
	};
	ext.runBuzzerJ2 = function(tone, beat){
		ext.runBuzzer(tone, beat);
	};
	ext.runBuzzerJ3 = function(tone, beat){
		ext.runBuzzer(tone, beat);
	};
	ext.runMP3 = function(track, loop) {
		runPackage(35,track,typeof loop=="string" ? onoff[loop]: new Number(loop));
	};
	ext.stopMP3 = function() {
		runPackage(36);
	};
	
	ext.getDigital = function(pin) {
		getPackage(30,pin);
	};
	ext.getDigitalA = function(pin) {
		getPackage(30,14+pin);
	};
	ext.getAnalog = function(pin) {
		getPackage(31,pin);
	};
	ext.checkRemoteKey = function() {
		getPackage(18);
	//	var startMsec = new Date();
	//	while (new Date() - startMsec < 100);
	}
	ext.isRemoteKey = function(code){
		if(typeof code=="string") {
			code = ircodes[code];
		}
		responseValue2(0,remoteKey==code);
	}
	ext.isARemoteKey = function(code){
		ext.isRemoteKey(code)
	}
	ext.getRemoteX = function(){
		responseValue2(0,remoteX);
	}
	ext.getRemoteY = function(){
		responseValue2(0,remoteY);
	}

	var lastCode = 0;
	function runPackage(){
		lastCode = 0;
		sendPackage(arguments, 2);
	}
	function getPackage(){
		lastCode = arguments[0];
		sendPackage(arguments, 1);
	}

	var comBusy = false;
	function sendPackage(argList, type){
		if(comBusy) {
	//		responseValue();
	//		return;
		}

		var bytes = [0xff, 0x55, 0, 0, type];
		for(var i=0;i<argList.length;++i){
			var val = argList[i];
			if(val.constructor == "[class Array]"){
				bytes = bytes.concat(val);
			}else{
				bytes.push(val);
			}
		}
		bytes[2] = bytes.length - 3;
		device.send(bytes);
		comBusy = true;
	}

	var _isParseStart = false;
	var _isParseStartIndex = 0;
	function processData(bytes) {
		var len = bytes.length;
		if(_rxBuf.length > 30){
			_rxBuf = [];
			_isParseStart = false;
		}
		for(var index = 0; index < bytes.length; index++){
			var c = bytes[index];
			_rxBuf.push(c);
			if(_rxBuf.length >= 2){
				if(!_isParseStart && _rxBuf[_rxBuf.length-1] == 0x55 && _rxBuf[_rxBuf.length-2] == 0xff){
					_isParseStart = true;
					_isParseStartIndex = _rxBuf.length-2;

				} else if(_isParseStart && _rxBuf[_rxBuf.length-1] == 0xa && _rxBuf[_rxBuf.length-2] == 0xd){
					
					if(_rxBuf.length < _isParseStartIndex+(2+1+1+1+2)) {
						responseValue();
					} else {
						var extId = _rxBuf[_isParseStartIndex+2];
						var type = _rxBuf[_isParseStartIndex+3];
						var value;
						switch(type){
						case 1:		// byte
							value = _rxBuf[_isParseStartIndex+4];
							if(lastCode == 18) {	// remote(old)
								remoteKey = value;
							}
							break;
						case 2:		// float
							value = readFloat(_rxBuf, _isParseStartIndex+4);
							break;
						case 3:		// short
							value = readInt(_rxBuf, _isParseStartIndex+4, 2);
							break;
						case 4:		// string
							value = readString(_rxBuf, _isParseStartIndex+5, _rxBuf[_isParseStartIndex+4]);
							break;
						case 5:		// double
							value = readDouble(_rxBuf, _isParseStartIndex+4);
							break;
						case 6:		// long
							value = readInt(_rxBuf, _isParseStartIndex+4, 4);
							break;
						case 7:		// remote
							value = _rxBuf[_isParseStartIndex+4];
							remoteKey = value;
							remoteX = readInt(_rxBuf, _isParseStartIndex+5, 2);
							remoteY = readInt(_rxBuf, _isParseStartIndex+7, 2);
						}
						responseValue(extId,value);
					}
					_rxBuf = [];
					_isParseStart = false;
					comBusy = false;
				}
			} 
		}
	}
	function readFloat(arr,position){
		var f= [arr[position],arr[position+1],arr[position+2],arr[position+3]];
		return parseFloat(f);
	}
	function readInt(arr,position,count){
		var result = 0;
		for(var i=0; i<count; ++i){
			result |= arr[position+i] << (i << 3);
		}
		if(arr[position+i-1] & 0x80) {
			result -= 1 << (i << 3);
		}
		return result;
	}
	function readDouble(arr,position){
		return readFloat(arr,position);
	}
	function readString(arr,position,len){
		var value = "";
		for(var ii=0;ii<len;ii++){
			value += String.fromCharCode(_rxBuf[ii+position]);
		}
		return value;
	}
	function appendBuffer( buffer1, buffer2 ) {
		return buffer1.concat( buffer2 );
	}

	// Extension API interactions
	var potentialDevices = [];
	ext._deviceConnected = function(dev) {
		potentialDevices.push(dev);
		if (!device) {
			tryNextDevice();
		}
	}

	function tryNextDevice() {
		// If potentialDevices is empty, device will be undefined.
		// That will get us back here next time a device is connected.
		device = potentialDevices.shift();
		if (device) {
			device.open({ stopBits: 0, bitRate: 115200, ctsFlowControl: 0 }, deviceOpened);
		}
	}

	var watchdog = null;
	function deviceOpened(dev) {
		if (!dev) {
			// Opening the port failed.
			tryNextDevice();
			return;
		}
		device.set_receive_handler('makeblock',processData);
	};

	ext._deviceRemoved = function(dev) {
		if(device != dev) return;
		device = null;
	};

	ext._shutdown = function() {
		if(device) device.close();
		device = null;
	};

	ext._getStatus = function() {
		if(!device) return {status: 1, msg: 'RemoconRobo disconnected'};
		if(watchdog) return {status: 1, msg: 'Probing for RemoconRobo'};
		return {status: 2, msg: 'RemoconRobo connected'};
	}
	var descriptor = {};
	ScratchExtensions.register('RemoconRobo', descriptor, ext, {type: 'serial'});
})({});
