// mBot.js

(function(ext) {
    var device = null;
    var _rxBuf = [];

	var levels = {"HIGH":1,"LOW":0};
	var onoff = {"On":1,"Off":0};
	var directions = {"run forward":0,"turn left":1,"turn right":2,"run backward":3};
	var tones ={"C2":65,"D2":73,"E2":82,"F2":87,"G2":98,"A2":110,"B2":123,
			"C3":131,"D3":147,"E3":165,"F3":175,"G3":196,"A3":220,"B3":247,
			"C4":262,"D4":294,"E4":330,"F4":349,"G4":392,"A4":440,"B4":494,
			"C5":523,"D5":587,"E5":659,"F5":698,"G5":784,"A5":880,"B5":988,
			"C6":1047,"D6":1175,"E6":1319,"F6":1397,"G6":1568,"A6":1760,"B6":1976,
			"C7":2093,"D7":2349,"E7":2637,"F7":2794,"G7":3136,"A7":3520,"B7":3951,
			"C8":4186,"D8":4699};
	var tonesJ ={"ド2":65,"レ2":73,"ミ2":82,"ファ2":87,"ソ2":98,"ラ2":110,"シ2":123,
			"ド3":131,"レ3":147,"ミ3":165,"ファ3":175,"ソ3":196,"ラ3":220,"シ3":247,
			"ド4":262,"レ4":294,"ミ4":330,"ファ4":349,"ソ4":392,"ラ4":440,"シ4":494,
			"ド5":523,"レ5":587,"ミ5":659,"ファ5":698,"ソ5":784,"ラ5":880,"シ5":988,
			"ド6":1047,"レ6":1175,"ミ6":1319,"ファ6":1397,"ソ6":1568,"ラ6":1760,"シ6":1976,
			"ド7":2093,"レ7":2349,"ミ7":2637,"ファ7":2794,"ソ7":3136,"ラ7":3520,"シ7":3951,
			"ド8":4186,"レ8":4699};
	var beats = {"Half":500,"Quarter":250,"Eighth":125,"Whole":1000,"Double":2000,"Zero":0};
	var ircodes = {	"A":69,"B":70,"C":71,"D":68,"E":67,"F":13,"↑":64,"↓":25,"←":7,"→":9,"CENTER":21,
		"R0":22,"R1":12,"R2":24,"R3":94,"R4":8,"R5":28,"R6":90,"R7":66,"R8":82,"R9":74};
	var key = 0;
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
	ext.runMotor = function(port,speed) {
        runPackage(10,port,short2array(speed));
    };
	ext.runDigital = function(pin,level) {
        runPackage(30,pin,typeof level == "string"?levels[level]:new Number(level));
    };
	ext.runServoArduino = function(pin, angle){
		runPackage(33,pin,angle);
	};
	ext.runLED= function(level) {
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
	ext.runBuzzerJ = function(tone, beat){
		if(typeof tone == "string"){
			tone = tonesJ[tone];
		}
		if(typeof beat == "string"){
			beat = parseInt(beat) || beats[beat];
		}
		runPackage(34,short2array(tone), short2array(beat));
	};
	
	ext.getDigital = function(pin) {
		getPackage(30,pin);
	};
	ext.getAnalog = function(pin) {
		getPackage(31,pin);
    };
	ext.checkRemote = function(code){
		if(typeof code=="string") {
			code = ircodes[code];
		}
	//	getPackage(14,code);
		responseValue(0,key==code);
	}
	ext.getRemote = function() {
		getPackage(18);
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
		if(_rxBuf.length>30){
			_rxBuf = [];
		}
		for(var index=0;index<bytes.length;index++){
			var c = bytes[index];
			_rxBuf.push(c);
			if(_rxBuf.length>=2){
				if(_rxBuf[_rxBuf.length-1]==0x55 && _rxBuf[_rxBuf.length-2]==0xff){
					_isParseStart = true;
					_isParseStartIndex = _rxBuf.length-2;
				}
				if(_rxBuf[_rxBuf.length-1]==0xa && _rxBuf[_rxBuf.length-2]==0xd&&_isParseStart){
					_isParseStart = false;
					
					var position = _isParseStartIndex+2;
					var extId = _rxBuf[position];
					position++;
					var type = _rxBuf[position];
					position++;
					//1 byte 2 float 3 short 4 len+string 5 double
					var value;
					switch(type){
						case 1:{
							value = _rxBuf[position];
							position++;
						}
							break;
						case 2:{
							value = readFloat(_rxBuf,position);
							position+=4;
						}
							break;
						case 3:{
							value = readInt(_rxBuf,position,2);
							position+=2;
						}
							break;
						case 4:{
							var l = _rxBuf[position];
							position++;
							value = readString(_rxBuf,position,l);
						}
							break;
						case 5:{
							value = readDouble(_rxBuf,position);
							position+=4;
						}
							break;
						case 6:
							value = readInt(_rxBuf,position,4);
							position+=4;
							break;
					}
					if(type<=6){
						if(lastCode == 18) {
							key = value;
						}
						responseValue(extId,value);
					}else{
						responseValue();
					}
					_rxBuf = [];
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
        if(!device) return {status: 1, msg: 'mBot disconnected'};
        if(watchdog) return {status: 1, msg: 'Probing for mBot'};
        return {status: 2, msg: 'mBot connected'};
    }
    var descriptor = {};
	ScratchExtensions.register('FamilyDay', descriptor, ext, {type: 'serial'});
})({});
