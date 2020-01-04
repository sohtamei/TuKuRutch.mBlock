// remoconRobo.js

(function(ext) {
	var device = null;
	var checkDevName = false;
	var devName = "";

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
	
	var stype = {
		GET		: 1,
		RUN		: 2,
		RESET	: 4,
		START	: 5,
	};

	var cmd = {
		// get, run
		DIGITAL		: 30,

		// get
		VERSION		: 0,
		CHECKREMOTEKEY	: 18,
		ANALOG		: 31,
		GETCALIB	: 37,
		ANALOGAVE	: 40,

		// run
		ROBOT		: 5,
		MOTOR		: 10,
	//	PWM			: 32,
		SERVO		: 33,
		TONE		: 34,
		PLAYMP3		: 35,
		STOPMP3		: 36,
		SETCALIB	: 38,
		INCCALIB	: 39,
	};

	ext.resetAll = function(){
		device.send([0xff, 0x55, 2, 0, stype.RESET]);
	};
	ext.runArduino = function(){
		responseValue();
	};
	ext.runRobot = function(direction,speed) {
		if(typeof direction == "string"){
			direction = directions[direction];
		}
		sendPackage(stype.RUN, cmd.ROBOT, direction, speed);
	};
	ext.stopRobot= function() {
		sendPackage(stype.RUN, cmd.ROBOT, 0,0);
	}
	ext.runMotor = function(port,speed) {
		sendPackage(stype.RUN, cmd.MOTOR, port, short2array(speed));
	};

	ext.runCalibRight = function(inc) {
		sendPackage(stype.RUN, cmd.INCCALIB, short2array(inc));
	};
	ext.runCalibLeft = function(inc) {
		sendPackage(stype.RUN, cmd.INCCALIB, short2array(-inc));
	};
	ext.getCalib = function() {
		sendPackage(stype.GET, cmd.GETCALIB);
	};
	ext.runSetCalib = function(calib) {
		sendPackage(stype.RUN, cmd.SETCALIB, short2array(calib));
	};

	ext.runDigital = function(pin,level) {
		sendPackage(stype.RUN, cmd.DIGITAL, pin, typeof level == "string"?levels[level]:new Number(level));
	};
	ext.runDigitalA = function(pin,level) {
		sendPackage(stype.RUN, cmd.DIGITAL, 14+pin, typeof level == "string"?levels[level]:new Number(level));
	};
	ext.runServoArduino = function(pin, angle){
		sendPackage(stype.RUN, cmd.SERVO, pin, angle);
	};
	ext.runLED = function(level) {
		sendPackage(stype.RUN, cmd.DIGITAL, 13, typeof level == "string"?onoff[level]:new Number(level));
	};
	ext.runBuzzer = function(tone, beat){
		if(typeof tone == "string"){
			tone = tones[tone];
		}
		if(typeof beat == "string"){
			beat = parseInt(beat) || beats[beat];
		}
		sendPackage(stype.RUN, cmd.TONE, short2array(tone), short2array(beat));
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
		sendPackage(stype.RUN, cmd.PLAYMP3, track, typeof loop=="string" ? onoff[loop]: new Number(loop));
	};
	ext.stopMP3 = function() {
		sendPackage(stype.RUN, cmd.STOPMP3);
	};
	
	ext.getDigital = function(pin) {
		sendPackage(stype.GET, cmd.DIGITAL, pin);
	};
	ext.getDigitalA = function(pin) {
		sendPackage(stype.GET, cmd.DIGITAL, 14+pin);
	};
	ext.getAnalog = function(pin) {
		sendPackage(stype.GET, cmd.ANALOG, pin);
	};
	ext.getAnalogAve = function(pin, count) {
		sendPackage(stype.GET, cmd.ANALOGAVE, pin, short2array(count));
	};
	ext.checkRemoteKey = function() {
		sendPackage(stype.GET, cmd.CHECKREMOTEKEY);
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

	//************************************************
	// common

	var comBusy = false;
	function sendPackage(){
		checkDevName = false;

		if(comBusy) {
	//		responseValue();
	//		return;
		}

		var bytes = [0xff, 0x55, 0, 0];
		for(var i=0;i<arguments.length;++i){
			var val = arguments[i];
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

	var rtype = {
		BYTE	: 1,	// len=1
		FLOAT	: 2,	// len=4
		SHORT	: 3,	// len=2
		STRING	: 4,	// len=n (n, string[n])
		DOUBLE	: 5,	// len=8
		LONG	: 6,	// len=4
		REMOTE	: 7		// len=5 (key, x[2], y[2])
	};

	var _rxBuf = [];
	var _packetLen = 4;
	function processData(bytes) {
		if(checkDevName) {
			for(var index = 0; index < bytes.length; index++) {
				var c = bytes[index];
				if(c == 0x0d) {
					updateDevName(devName);
					checkDevName = false;
				} else {
					devName += String.fromCharCode(c);
				}
			}
			return;
		}

		for(var index = 0; index < bytes.length; index++){
			var c = bytes[index];
			_rxBuf.push(c);
			switch(_rxBuf.length) {
			case 1:
				_packetLen = 4;
				if(c != 0xff) 
					_rxBuf = [];
				break;
			case 2:
				if(c != 0x55) 
					_rxBuf = [];
				break;
			case 4:
				switch(_rxBuf[3]) {
				case rtype.BYTE:	_packetLen = 4+1+2;	break;
				case rtype.FLOAT:	_packetLen = 4+4+2;	break;
				case rtype.SHORT:	_packetLen = 4+2+2;	break;
				case rtype.STRING:	_packetLen = 4+1+2;	break;	// tentative
				case rtype.DOUBLE:	_packetLen = 4+8+2;	break;
				case rtype.LONG:	_packetLen = 4+4+2;	break;
				case rtype.REMOTE:	_packetLen = 4+5+2;	break;
			//	case 0x0a:	break;
				default:	break;
				}
				break;
			case 5:
				if(_rxBuf[3] == rtype.STRING)
					_packetLen = 4+1+_rxBuf[4]+2;
				break;
			}

			if(_rxBuf.length >= _packetLen) {
				if(_rxBuf[_rxBuf.length-1] == 0xa && _rxBuf[_rxBuf.length-2] == 0xd && _packetLen > 4) { 
					var value = 0;
					switch(_rxBuf[3]) {
					case rtype.BYTE:	value = _rxBuf[4];	break;
					case rtype.FLOAT:	value = readFloat(_rxBuf, 4);				break;
					case rtype.SHORT:	value = readInt(_rxBuf, 4, 2);				break;
					case rtype.STRING:	value = readString(_rxBuf, 5, _rxBuf[4]);	break;
					case rtype.DOUBLE:	value = readDouble(_rxBuf, 4);				break;
					case rtype.LONG:	value = readInt(_rxBuf, 4, 4);				break;
					case rtype.REMOTE:
						value = _rxBuf[4];
						remoteKey = value;
						remoteX = readInt(_rxBuf, 5, 2);
						remoteY = readInt(_rxBuf, 7, 2);
						break;
					}
					responseValue(_rxBuf[2],value);
				} else {
					responseValue();
				}
				_rxBuf = [];
				comBusy = false;
			}
		}
	}
	function readFloat(arr,position){
		var f= [arr[position+0],arr[position+1],arr[position+2],arr[position+3]];
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
		return readFloat(arr,position);		// ?
	}
	function readString(arr,position,len){
		var value = "";
		for(var ii=0;ii<len;ii++){
			value += String.fromCharCode(arr[ii+position]);
		}
		return value;
	}

	// Extension API interactions
	ext._deviceConnected = function(dev) {
		device = dev;
		if (device) {
			checkDevName = true;
			devName = "";
			device.open(115200, deviceOpened);
		}
	}

	function deviceOpened(dev) {
		device.set_receive_handler(processData);
	};

	ext._deviceRemoved = function(dev) {
		if(device != dev) return;
		device = null;
	};
/*
	ext._shutdown = function() {
		if(device) device.__close();
		device = null;
	};
*/
//	var watchdog = null;
	ext._getStatus = function() {
		if(!device) return {status: 1, msg: 'RemoconRobo disconnected'};
	//	if(watchdog) return {status: 1, msg: 'Probing for RemoconRobo'};
		return {status: 2, msg: 'RemoconRobo connected'};
	}
	var descriptor = {};
	ScratchExtensions.register('RemoconRobo', descriptor, ext, {type: 'serial'});
})({});
