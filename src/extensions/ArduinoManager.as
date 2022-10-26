package extensions
{
	import flash.desktop.NativeProcess;
	import flash.desktop.NativeProcessStartupInfo;
	import flash.events.Event;
	import flash.events.EventDispatcher;
	import flash.events.NativeProcessExitEvent;
	import flash.events.ProgressEvent;
	import flash.filesystem.File;
	import flash.filesystem.FileMode;
	import flash.filesystem.FileStream;
	import flash.utils.getQualifiedClassName;
	
	import blocks.Block;
	import blocks.BlockIO;
	
	import cc.makeblock.mbot.util.PopupUtil;
	import cc.makeblock.mbot.util.StringUtil;
	import cc.makeblock.util.FileUtil;
	
	import translation.Translator;
	
	import util.ApplicationManager;
	import util.JSON;
	import uiwidgets.DialogBox;

	public class ArduinoManager extends EventDispatcher
	{
		private static var _instance:ArduinoManager;
		public var _scratch:Main;
		
		private var process:NativeProcess;
		public var hasUnknownCode:Boolean = false;
		private var ccode_setup:String = "";
		private var ccode_setup_fun:String = "";
		private var ccode_loop:String = "";
		private var ccode_def:String = "";
		private var ccode_pointer:String="setup";
		//添加 && ||
		private var mathOp:Array=["+","-","*","/","%",">","=","<","&","&&","|","||","!","not","rounded"];
		private var varList:Array = [];
		private var varStringList:Array = [];
		private var moduleList:Array=[];
		private var funcList:Array = [];
		
		public var unknownBlocks:Array = [];
		
		// maintance of project and arduino path
		
		public var mainX:int = 0;
		public var mainY:int = 0;
		
		public static function sharedManager():ArduinoManager{
			if(_instance==null){
				_instance = new ArduinoManager;
			}
			return _instance;
		} 
		
		public function ArduinoManager()
		{
		}
		
		public function clearTempFiles():void
		{
			if(File.applicationStorageDirectory.exists){
				File.applicationStorageDirectory.deleteDirectory(true);
			}
			PopupUtil.showConfirm(Translator.map("Restart mBlock?"),Main.app.restart);
		}
		
		public function setScratch(scratch:Main):void{
			_scratch = scratch;
		}
		private function parseMath(blk:Object):CodeObj{
			var op:Object= blk[0];
			var mp1:CodeBlock=getCodeBlock(blk[1]);
			var mp2:CodeBlock=getCodeBlock(blk[2]);
			if(op=="="){
				op="==";
			}
			if(mp1.type=="string"){
				if(!isNaN(Number(mp1.code))){
					mp1.type = "number";
					mp1.code = Number(mp1.code);
				}
			}
			if(mp2.type=="string"){
				if(!isNaN(Number(mp2.code))){
					mp2.type = "number";
					mp2.code = Number(mp2.code);
				}
			}
			var code:String = StringUtil.substitute("({0}) {1} ({2})",mp1.type=="obj"?mp1.code.code:mp1.code ,op,mp2.type=="obj"?mp2.code.code:mp2.code);
			if(op=="=="){
				if(mp1.type=="string"&&mp2.type=="string"){
					code = StringUtil.substitute("({0}.equals(\"{1}\"))",mp1.code,mp2.code);
				}else{
					code = StringUtil.substitute("(({0})==({1}))",mp1.type=="obj"?mp1.code.code:mp1.code,mp2.type=="obj"?mp2.code.code:mp2.code);
				}
			}else if(op=="%"){
				code = StringUtil.substitute("fmod({0},{1})",mp1.type=="obj"?mp1.code.code:mp1.code,mp2.type=="obj"?mp2.code.code:mp2.code);
			}else if(op=="not"){
				code = StringUtil.substitute("!({0})",mp1.type=="obj"?mp1.code.code:mp1.code);
			}else if(op=="rounded"){
				code = StringUtil.substitute("round({0})",mp1.type=="obj"?mp1.code.code:mp1.code);
			}
			return new CodeObj(code);
		}
		
		
		private function parseVarRead(blk:Object):CodeObj{
			var varName:Object = blk[1];
			if(varList.indexOf(varName)==-1){
				varList.push(varName);
			}
			var code:CodeObj = new CodeObj(StringUtil.substitute("{0}",castVarName(varName.toString())));
			return code;
		}
		
		private function parseVarSet(blk:Object):String{
			var varName:String = blk[1];
			if(varList.indexOf(varName)==-1)
				varList.push(varName);
			var varValue:* = blk[2] is CodeObj?blk[2].code:blk[2];
			if(getQualifiedClassName(varValue)=="Array"){
				varValue = getCodeBlock(varValue);
				if(varValue.type=="obj"){
				//	if(varValue.code.code.indexOf("ir.getString()")>-1){
				//		varStringList.push(varName);
				//	}
				}else if(varValue.type=="string"){
					if(varStringList.indexOf(varName)==-1){
						varStringList.push(varName);
					}
				}
				return (StringUtil.substitute("{0} = {1};\n", castVarName(varName), varValue.type=="obj"?varValue.code.code: varValue.code));
			}else{
				return (StringUtil.substitute("{0} = {1};\n", castVarName(varName), varValue is CodeObj?varValue.code: varValue));
			}
		}
		private function parseDelay(fun:Object):String{
			var cBlk:CodeBlock=getCodeBlock(fun[1]);
			var funcode:String=(StringUtil.substitute("_delay({0});\n", cBlk.type=="obj"?cBlk.code.code: cBlk.code));
			return funcode;
		}
		private function parseDoRepeat(blk:Object):String{
			var initCode:CodeBlock = getCodeBlock(blk[1]);
			var repeatCode:String=StringUtil.substitute("for(int __i__=0;__i__<{0};++__i__)\n{\n", initCode.type=="obj"?initCode.code.code: initCode.code);
			if(blk[2]!=null){
				for(var i:int=0;i<blk[2].length;i++){
					var b:Object = blk[2][i];
					var cBlk:CodeBlock=getCodeBlock(b);
					repeatCode+=cBlk.type=="obj"?cBlk.code.code: cBlk.code;
				}
			}
			repeatCode+="}\n";
			return repeatCode;
		}
		private function parseDoWaitUntil(blk:Object):String{
			var initCode:CodeBlock = getCodeBlock(blk[1]);
			var untilCode:String=StringUtil.substitute("while(!({0}))\n{\n_loop();\n}\n", initCode.type=="obj"?initCode.code.code: initCode.code);
			return (untilCode);
		}
		private function parseDoUntil(blk:Object):String{
			var initCode:CodeBlock = getCodeBlock(blk[1]);
			var untilCode:String=StringUtil.substitute("while(!({0}))\n{\n_loop();\n", initCode.type=="obj"?initCode.code.code: initCode.code);
			if(blk[2]!=null){
				for(var i:int=0;i<blk[2].length;i++){
					var b:Object = blk[2][i];
					var cBlk:CodeBlock=getCodeBlock(b);
					untilCode+=cBlk.type=="obj"?cBlk.code.code: cBlk.code;
				}
			}
			untilCode+="}\n";
			return (untilCode);
		}
		private function parseCall(blk:Object):String{
			
			var vars:String = "";
			var funcName:String = blk[1];
			if(funcName.indexOf("%")==0){
				funcName = "func "+funcName;
			}
			var ps:Array = funcName.split(" ");
			var tmp:Array = [castVarName(ps[0], true)];
			for(var i:uint=0;i<ps.length;i++){
				if(i>0){
					if(ps[i].indexOf("%")>-1){
						tmp.push(ps[i].substr(1,1));
					}
				}
			}
			ps = tmp;
			var params:Array = blk as Array;
			var cBlk:CodeBlock;
			for(i = 2;i<params.length;i++){
				cBlk = getCodeBlock(params[i]);
				//				trace("p:",params[i],cBlk.type,"end");
				if(i>2){
					vars +=",";
				}
				if(cBlk.type=="obj"){
					vars += cBlk.code.code;
				}else if(cBlk.type=="string"){
					vars += '"' + cBlk.code + '"';
				}else{
					vars += cBlk.code;
					
				}
			}
			var callCode:String = StringUtil.substitute("{0}({1});\n",ps[0],vars);
			return (callCode);
		}
		private function addFunction(blks:Array):void{
			var funcName:String = blks[0][1].split("&").join("_");
			for each(var o:Object in funcList){ 
				if(o.name==funcName){
					return;
				}
			}
			if(funcName.indexOf("%")==0){
				funcName = "func "+funcName;
			}
			var params:Array = funcName.split(" ");
			var tmp:Array = [params[0]];
			for(var i:uint=0;i<params.length;i++){
				if(i>0){
					if(params[i].indexOf("%")>-1){
						tmp.push(params[i].substr(1,1));
					}
				}
			}
			params = tmp;
			var vars:String = "";
			for(i = 1;i<params.length;i++){
				vars += (params[i]=='n'?"double":
						(params[i]=='s'?"String":
						(params[i]=='b'?"boolean":"")))
						+" "+castVarName(blks[0][2][i-1].split(" ").join("_"))+(i<params.length-1?", ":"");
			}
			var defFunc:String = "void "+castVarName(params[0], true)+"("+vars+");\n";
			if(ccode_def.indexOf(defFunc)==-1){
				ccode_def+=defFunc;
			}
			var funcCode:String = "void "+castVarName(params[0], true)+"("+vars+")\n{\n";
			for(i=0;i<blks.length;i++){
				if(i>0){
					
					var b:CodeBlock = getCodeBlock(blks[i]);//,blks[0][2]);
					var code:String = (b.type=="obj"?b.code.code: b.code);
					funcCode+=code+"\n";
				}
			}
			funcCode+="}\n";
			funcList.push({name:funcName,code:funcCode});
		}
		private function parseIfElse(blk:Object):String{
			var codeIfElse:String = "";
			var logiccode:CodeBlock = getCodeBlock(blk[1]);
			codeIfElse+=StringUtil.substitute("if({0}){\n", logiccode.type=="obj"?logiccode.code.code: logiccode.code);
			if(blk[2]!=null){
				for(var i:int=0;i<blk[2].length;i++){
					var b:CodeBlock = getCodeBlock(blk[2][i]);
					var ifcode:String=(b.type=="obj"?b.code.code: b.code)+"";
					codeIfElse+=ifcode
				}
			}
			codeIfElse+="}else{\n";
			if(blk[3]!=null){
				for(i=0;i<blk[3].length;i++){
					b = getCodeBlock(blk[3][i]);
					var elsecode:String=(b.type=="obj"?b.code.code: b.code)+"";
					codeIfElse+=elsecode;
				}
			}
			codeIfElse+="}\n";
			return codeIfElse
		}
		
		private function parseIf(blk:Object):String{
			var codeIf:String = "";
			var logiccode:String = getCodeBlock(blk[1]).code;
			codeIf+=StringUtil.substitute("if({0}){\n",logiccode);
			if(blk is Array){
				if(blk.length>2){
					if(blk[2]!=null){
						for(var i:int=0;i<blk[2].length;i++){
							var b:CodeBlock = getCodeBlock(blk[2][i]);
							var ifcode:String=(b.type=="obj"?b.code.code: b.code)+"";
							codeIf+=ifcode;
						}
					}
				}
			}
			codeIf+="}\n";
			return codeIf
		}
		
		private function parseComputeFunction(blk:Object):String{
			var cBlk:CodeBlock = getCodeBlock(blk[2]);
			switch(blk[1]){
			case "10 ^":	return StringUtil.substitute("pow(10,{0})", cBlk.code);
			case "e ^":		return StringUtil.substitute("exp({0})",    cBlk.code);
			case "ceiling":	return StringUtil.substitute("ceil({0})",   cBlk.code);
			case "log":		return StringUtil.substitute("log10({0})",  cBlk.code);
			case "ln":		return StringUtil.substitute("log({0})",    cBlk.code);
			}
			return StringUtil.substitute("{0}({1})", getCodeBlock(blk[1]).code, cBlk.code)
											.split("sin(").join("sin(angle_rad*")
											.split("cos(").join("cos(angle_rad*")
											.split("tan(").join("tan(angle_rad*");
		}
		private function appendFun(funcode:*):void{
			//			if (c!="\n" && c!="}")
			//funcode+=";\n"
			var allowAdd:Boolean = funcode is CodeObj;
			funcode = funcode is CodeObj?funcode.code: funcode;
			
			if(funcode==null) return;
			if(funcode.length==0) return;
			if(funcode.charAt(funcode.length-1) != "\n")
				funcode += "\n";
			if(ccode_pointer=="setup"){
				ccode_setup_fun += funcode;
			}
			else if(ccode_pointer=="loop"){
				ccode_loop += funcode;
			}
		}
		
		private function getCodeBlock(blk:Object):CodeBlock{
			var code:CodeObj;
			var codeBlock:CodeBlock = new CodeBlock;
			if(blk==null||blk==""){
				codeBlock.type = "number";
				codeBlock.code = "0";
				return codeBlock;
			}
			else if(!(blk is Array)){
				codeBlock.code = ""+blk;
				codeBlock.type = isNaN(Number(blk))?"string":"number";
				return codeBlock;
			}
			else if(blk.length==0){
				codeBlock.type = "string";
				codeBlock.code = "";
				return codeBlock;
			}
			else if(blk.length==16){				// ?
				codeBlock.type = "array";
				codeBlock.code = blk;
				return codeBlock;
			}
			else if(mathOp.indexOf(blk[0])>=0){		// + - * / % > = < & && | || ! not rounded
				codeBlock.type = "obj";
				codeBlock.code = parseMath(blk);
				return codeBlock;
			}
			else if(blk[0]=="readVariable"){		// GET_VAR
				codeBlock.type = "obj";
				codeBlock.code = parseVarRead(blk);
				return codeBlock;
			}
			/*else if(blk[0]=="initVar:to:"){		// 
				codeBlock.type = "obj";
				codeBlock.code = null;
				var tmpCodeBlock:Object = {code:{setup:parseVarSet(blk)}};
				moduleList.push(tmpCodeBlock);
				return codeBlock;
			}*/
			else if(blk[0]=="setVar:to:"){			// SET_VAR, set %m.var to %s
				codeBlock.type = "string";
				codeBlock.code = parseVarSet(blk);
				return codeBlock;
			}
			else if(blk[0]=="wait:elapsed:from:"){	// wait %n secs
				codeBlock.type = "string";
				codeBlock.code = parseDelay(blk);
				return codeBlock;
			}
			else if(blk[0]=="doIfElse"){			// if %b then .. else
				codeBlock.type = "string";
				codeBlock.code = parseIfElse(blk);
				return codeBlock;
			}
			else if(blk[0]=="doIf"){				// if %b then
				codeBlock.type = "string";
				codeBlock.code = parseIf(blk);
				return codeBlock;
			}
			else if(blk[0]=="doRepeat"){			// repeat %n
				codeBlock.type = "string";
				codeBlock.code = parseDoRepeat(blk);
				return codeBlock;
			}
			/*else if(blk[0]=="doForever"){			// forever
				codeBlock.type = "string";
				codeBlock.code = parseForever(blk);
				return codeBlock;
			}*/
			else if(blk[0]=="doWaitUntil"){			// wait until %b
				codeBlock.type = "string";
				codeBlock.code = parseDoWaitUntil(blk);
				return codeBlock;
			}
			else if(blk[0]=="doUntil"){				// repeat until %b
				codeBlock.type = "string";
				codeBlock.code = parseDoUntil(blk);
				return codeBlock;
			}
			else if(blk[0]=="call"){				// CALL
				codeBlock.type = "obj";//修复新建的模块指令函数，无法重复调用
				codeBlock.code = new CodeObj(parseCall(blk));
				return codeBlock;
			}
			else if(blk[0]=="randomFrom:to:"){		// pick random %n to %n
				codeBlock.type = "number";
				//as same as scratch, include max value
				codeBlock.code = StringUtil.substitute("random({0},({1})+1)", getCodeBlock(blk[1]).code, getCodeBlock(blk[2]).code);
				return codeBlock;
			}
			else if(blk[0]=="computeFunction:of:"){	// %m.mathOp of %n
				codeBlock.type = "number";
				codeBlock.code = parseComputeFunction(blk);
				return codeBlock;
			}
			else if(blk[0]=="concatenate:with:"){	// join %s %s
				var s1:CodeBlock = getCodeBlock(blk[1]);
				var s2:CodeBlock = getCodeBlock(blk[2]);
				codeBlock.type = "obj";
				codeBlock.code = new CodeObj(StringUtil.substitute("{0}+{1}",
															(s1.type=="obj")?s1.code.code: 'String("'+s1.code+'")',
															(s2.type=="obj")?s2.code.code: 'String("'+s2.code+'")'));
				return codeBlock;
			}
			else if(blk[0]=="letter:of:"){			// letter %n of %s
				s2 = getCodeBlock(blk[2]);
				codeBlock.type = "obj";
				codeBlock.code = new CodeObj(StringUtil.substitute("({1}).charAt({0}-1)",
															getCodeBlock(blk[1]).code,
															(s2.type=="obj")?s2.code.code: 'String("'+s2.code+'")'));
				return codeBlock;
			}
			else if(blk[0]=="castDigitToString:"){	// cast %n to string
				codeBlock.type = "obj";
				codeBlock.code = new CodeObj(StringUtil.substitute('String({0})',
															getCodeBlock(blk[1]).code));
				return codeBlock;
			}
			else if(blk[0]=="stringLength:"){		// length of %s
				s1 = getCodeBlock(blk[1]);
				codeBlock.type = "obj";
				codeBlock.code = new CodeObj(StringUtil.substitute("({0}).length()",
															(s1.type=="obj")?s1.code.code: 'String("'+s1.code+'")'));
				return codeBlock;
			}
			else if(blk[0]=="changeVar:by:"){		// CHANGE_VAR, change %m.var by %n
				codeBlock.type = "string";
				codeBlock.code = StringUtil.substitute("{0} += {1};\n",
															getCodeBlock(castVarName(blk[1])).code,
															getCodeBlock(blk[2]).code);
				return codeBlock;
			}

			var objs:Array = Main.app.extensionManager.specForCmd(blk[0]);
			if(objs!=null){
				var obj:Object = objs[objs.length-1];	//  spec[1]:"play tone ..",
														//  spec[0]:"w",
														//  extensionsCategory:20,
														//  prefix+spec[2]:"remoconRobo.runBuzzerJ2",
														//★spec.slice(3):(初期値+obj)
				var obj2:Object = obj[obj.length-1];	// 初期値, .. ★obj
				if(typeof obj2=="object"){
					var argTypes:Array = [];
					if(obj2.hasOwnProperty("remote"))
						argTypes = getProp(obj2,'remote');
					var ext:ScratchExtension = Main.app.extensionManager.extensionByName();//blk[0].split(".")[0]);
					var codeObj:Object = {code:{setup:_substitute(getProp(obj2,'setup'), blk as Array, ext, argTypes, objs[0]),
												func :_substitute(getProp(obj2,'func'),  blk as Array, ext, argTypes, objs[0])}};
					if(!availableBlock(codeObj)){	// 重複チェック
						moduleList.push(codeObj);
					}
					codeBlock.type = "obj";
					codeBlock.code = new CodeObj(codeObj.code.func);
					if(codeBlock.code.code.charAt(codeBlock.code.code.length-1) == ";")
						codeBlock.code.code+="\n";
					return codeBlock;
				}
			}

			var b:Block = BlockIO.arrayToStack([blk]);
			if(b.op=="getParam"){			// GET_PARAM
				codeBlock.type = "number";
				codeBlock.code = castVarName(b.spec.split(" ").join("_"));
				return codeBlock;
			}
			else if(b.op=="procDef"){		// PROCEDURE_DEF
				return codeBlock;
			}

			unknownBlocks.push(b);
			hasUnknownCode = true;
			codeBlock.type = "string";
			codeBlock.code = StringUtil.substitute("//unknow {0}{1}", blk[0], b.type=='r'?"":"\n");
			return codeBlock;
		}
		private function getProp(obj:Object, key:String):*{
			return obj.hasOwnProperty(key) ? obj[key] : "";
		}
		// デファインをext.valuesで展開し、"remoconRobo_tone({0},{1});\n" の{0},{1}を展開
		private function _substitute(str:String, params:Array, ext:ScratchExtension, argTypes:Array, blockDef:String):String{
			if(str == "") return "";

			var blockDefs:Array = blockDef.split("%");
			for(var i:uint=0; i < params.length-1; i++){
				var s:CodeBlock = getCodeBlock(params[i+1]);
				var argType:String = "";

				//  %d-数値+enum, %m-文字列+enumのときvaluesで置換
				if(i+1 < blockDefs.length) {
					argType = blockDefs[i+1].charAt(0);
					if(argType == "d" || argType == "m") {
						if(s.type == "string" && ext.values[s.code] != undefined)
							s.code = ext.values[s.code];
					}
				}

				argType = (i < argTypes.length) ? argTypes[i]: "";
				if(argType == "s") {
					if(s.type == "string")
						s.code = '"'+s.code+'"';
					else if(s.type == "obj")		// String("hello ")+String("world")
						s.code = s.code.code;
				} else if(argType.slice(0,1) == "b") {
					var j:int;
					var tmp:String = "";
					for(j = 0; j < s.code.length; j+=2)
						tmp += "\\x" + s.code.substr(j,2);
					s.code = '"'+tmp+'",'+j/2;
				} else {
				// B-int8, S-int16, L-int32, F-float, D-double
					switch(s.type) {
					case "number":
						if(s.code==""||s.code==" ")
							s.code = "0";
						break;
					case "string":
						if(!isNaN(Number(s.code)))
							s.code = Number(s.code);
						break;
					case "code":
						break;
					}
				}
				str = str.split("{"+i+"}").join(s.code);
			}
			return str;
		}
		private function availableBlock(obj:Object):Boolean{
			for each(var o:Object in moduleList){
				if(o.code.setup==obj.code.setup){
					return true;
				}
			}
			return false;
		}
		private function parseLoop(blks:Object):void{
			ccode_pointer="loop";
			if(blks!=null){
				for(var i:int;i<blks.length;i++){
					var b:Object = blks[i];
					var cBlk:CodeBlock = getCodeBlock(b);
					appendFun(cBlk.code);
				}
			}
		}
		private function parseModules(blks:Object):void{
			var isArduinoCode:Boolean = false;
			for(var i:int;i<blks.length;i++){
				var b:Object = blks[i];
				var objs:Array = Main.app.extensionManager.specForCmd(blks[0]);
				if(objs!=null){
					var obj:Object = objs[objs.length-1];
					obj = obj[obj.length-1];
					if(typeof obj == "object"&&obj!=null){
						var codeObj:Object = {code:{setup:getProp(obj,'setup'),
													func :getProp(obj,'func')}};
						moduleList.push(codeObj);
					}
				}
			}
		}
		private function parseCodeBlocks(blks:Object):Boolean{
			var isArduinoCode:Boolean = false;
			for(var i:int;i<blks.length;i++){
				var b:Object = blks[i];
				var op:String = b[0];
				if(op.indexOf("runArduino")>-1){
					ccode_pointer="setup";
					isArduinoCode = true;
				}else if(op=="doForever"){
					ccode_pointer="loop";
					parseLoop(b[1]);
				}else{
					var cBlk:CodeBlock = getCodeBlock(b);
					appendFun(cBlk.code);
				}
			}
			return isArduinoCode;
		}
		private function fixTabs(code:String):String{
			var tmp:String = "";
			var tabindex:int=0;
			var newLineList:Array = [];
			var lines:Array = code.split('\n');
			for(var i:int=0;i<lines.length;i++){
				var l:String = lines[i];
				if(l.indexOf("}")>=0)
					tabindex-=1;
				tmp = "";
				for(var j:int=0;j<tabindex;j++)
					tmp+="    ";
				newLineList.push(tmp+l);
				if(l.indexOf("{")>=0)
					tabindex+=1;
			}
			code = newLineList.join("\n");
			code = code.replace(new RegExp("\r\n", "gi"),"\n") // replace windows type end line
			return code;
		}
		private function fixVars(code:String):String{
			for each(var s:String in varStringList){
				code = code.split("double " +s).join("String "+s);
			}
			return code;
		}
		private var codeTemplate:String = ( <![CDATA[
// HEADER
// DEFINE
// FUNCTION
void setup(){
// SETUP1
Serial.println("Arduino: " mVersion);
// SETUP2
}

void loop(){
// LOOP1
// LOOP2
_loop();
}

void _delay(float seconds){
long endTime = millis() + seconds * 1000;
while(millis() < endTime) _loop();
}

void _loop(){
}

]]> ).toString();

		public function jsonToCpp(code:String):String{
			// reset code buffers 
			ccode_def="";
			ccode_setup="";
			ccode_setup_fun = "";
			ccode_loop="";
			hasUnknownCode = false;
			// reset arrays
			varList=[];
			varStringList=[];
			moduleList=[];
			funcList = [];
			unknownBlocks = [];
			// params for compiler
			var buildSuccess:Boolean = false;
			var objs:Object = util.JSON.parse(code);
			var childs:Array = objs.children.reverse();
			for(var i:int=0;i<childs.length;i++){
				buildSuccess = parseScripts(childs[i].scripts);
			}
			if(!buildSuccess){
				parseScripts(objs.scripts);
			}
			var ccode_func:String = ccode_func=buildFunctions();
		//	ccode_setup = hackVaribleWithPinMode(ccode_setup);
			var ext:ScratchExtension = Main.app.extensionManager.extensionByName();
			var retcode:String = codeTemplate
									.replace("// HEADER", getProp(ext, "header"))
									.replace("// DEFINE", ccode_def)
									.replace("// FUNCTION",ccode_func)
									.replace("// SETUP1", getProp(ext, "setup"))
									.replace("// SETUP2", ccode_setup)
									.replace("// LOOP1", getProp(ext, "loop"))
									.replace("// LOOP2", ccode_loop);
			retcode = fixTabs(retcode);
			retcode = fixVars(retcode);
			
			// now go into compile process
			if(!NativeProcess.isSupported) return "";
			return (retcode);
		}
		
		public function jsonToJs():Boolean
		{
			var ext:ScratchExtension = Main.app.extensionManager.extensionByName();
			if(!ext.scratch3ext) return false;

			var define:String = "";
			var flashes:String = "";
			var _blocks:String = "";
			var menus:String = "";
			var funcs:String = "";
			var i:int;
			var f:File;

			var extNames:Array = ext.scratch3ext.split(",");
			define = "var extName = '" + extNames[0] + "';\n";
			if(extNames.length >= 2) {
				define += "const " + extNames[1] + " = true;\n";
			} else {
				define += "const SupportCamera = false;\n";
			}

			var copyFiles:String = "";
			for(i=0; i<ext.scratch3burn.length; i++) {
				var imageName:String = ext.scratch3burn[i].name;
				copyFiles += imageName+", ";

				//{name:'TukuBoard1.0', type:'esp32', baudrate:230400},

				flashes += "{name:'"+ext.scratch3burn[i].name
							+"', type:'"+ext.scratch3burn[i].type
							+"', baudrate:"+ext.scratch3burn[i].baudrate+"},\n";

				var pcmodeFWpath:String = "ext/libraries/"+ext.scratch3burn[i].binPath+"/"+ext.pcmodeFW.replace(ext.docPath,"");
				var pcmodeBuildPath:String = "ext/libraries/"+ext.scratch3burn[i].binPath+"/build/"+ext.pcmodeFW.replace(ext.docPath,"");
				switch(ext.scratch3burn[i].type) {
				case 'esp32':
				case 'esp32c3':
				case 'esp32s3':
					f = File.applicationDirectory.resolvePath(pcmodeFWpath+".ino.bootloader.bin");
					if(f.exists)
						f.copyTo(new File(getNativePath("ext/scratch3/"+imageName+".boot.bin")), true);

					f = File.applicationDirectory.resolvePath(pcmodeFWpath+".ino.partitions.bin");
					if(f.exists)
						f.copyTo(new File(getNativePath("ext/scratch3/"+imageName+".part.bin")), true);

					f = File.applicationDirectory.resolvePath(pcmodeFWpath+".ino."+ext.scratch3burn[i].type+".bin");
					if(f.exists)
						f.copyTo(new File(getNativePath("ext/scratch3/"+imageName+".image.bin")), true);
					break;
				case 'avr':
				case 'samd':
					f = File.applicationDirectory.resolvePath(pcmodeFWpath+".ino.standard.hex");
					if(f.exists)
						f.copyTo(new File(getNativePath("ext/scratch3/"+imageName+".hex")), true);
					break;
				}
			}
			if(ext.scratch3burn.length==0) {
				flashes += "{name:'dummy', type:'', baudrate:0},\n";
			} else {
				Main.app.scriptsPart.appendMessage("copy bin:"+copyFiles);
			}

			for(i=1; i<ext.blockSpecsSize; i++) {
//		["w", "set LED %d.led %d.onoff", "setLED", 1,"On", {"remote":["B","B"],	"func":"_setLED({0},{1});"}],

				var spec:Array = ext.blockSpecs[i];
				if(spec.length < 3){
					if(spec[0] == "-") _blocks += "'---',\n";
					continue;
				}

				var txtEnOrg:String = spec[1];
				var txtEnNew:String = "";
				var txtJpOrg:String = "";
				var txtJpNew:String = "";
				var args:Array = new Array();

				if(ext.translators.ja.hasOwnProperty(txtEnOrg))
					txtJpOrg = ext.translators.ja[txtEnOrg];
				
				var pos:int;
				var j:int;
				for(j = 0;;j++) {
					pos = txtEnOrg.indexOf("%");
					if(pos == -1) {
						txtEnNew += txtEnOrg;
						break;
					}
					txtEnNew += txtEnOrg.slice(0,pos) + "[ARG" + (j+1) + "]";
					txtEnOrg = txtEnOrg.slice(pos);

					pos = txtEnOrg.indexOf(" ");
					if(pos == -1) {
						args.push(txtEnOrg);
						txtEnOrg = "";
					} else {
						args.push(txtEnOrg.slice(0,pos));
						txtEnOrg = txtEnOrg.slice(pos);
					}
				}
				var argNum:int = j;
				for(j = 0;j < argNum;j++) {
					pos = txtJpOrg.indexOf(args[j]);
					if(pos == -1) {
						txtJpNew = "";
						break;
					}
					txtJpNew += txtJpOrg.slice(0,pos) + "[ARG" + (j+1) + "]";
					txtJpOrg = txtJpOrg.slice(pos + args[j].length);
				}
				if(j == 0) txtJpNew = txtJpOrg;
				else if(txtJpNew != "") txtJpNew += txtJpOrg;

				var obj:Object = spec[spec.length-1];
				var types:Array = new Array();
				if(obj.hasOwnProperty("enum")) {
					 types.push("B");
					funcs += spec[2] + "(args) { return args.ARG1; }\n";
				} else if(obj.hasOwnProperty("remote")) {
					types = obj["remote"];
					if(types.length < argNum)
						continue;
					funcs += spec[2] + "(args,util) { return this.sendRecv('" + spec[2] + "', args); }\n";
				} else if(obj.hasOwnProperty("custom")) {
					_blocks += "'---',\n";
					continue;
				} else {
					_blocks += "'---',\n";
					continue;
				}

				switch(spec[0]) {
				case "w":
					_blocks += "{blockType: BlockType.COMMAND, opcode: '" + spec[2] + "', text: ";
					break;
				case "R":
				case "r":
					_blocks += "{blockType: BlockType.REPORTER, opcode: '" + spec[2] + "', text: ";
					break;
				case "B":
					_blocks += "{blockType: BlockType.BOOLEAN, opcode: '" + spec[2] + "', text: ";
					break;
				}
				if(txtJpNew == "") {
					_blocks += "'" + txtEnNew + "', arguments: {\n";
				} else {
					_blocks += "[\n";
					_blocks += "    '" + txtEnNew + "',\n";
					_blocks += "    '" + txtJpNew + "',\n";
					_blocks += "][this._locale], arguments: {\n";
				}

				for(j = 0;j < argNum;j++) {
			//	ARG1: { type: ArgumentType.NUMBER, menu: 'led',	defaultValue:1,		type2:"B" },
					pos = args[j].indexOf(".");
					_blocks += "    ARG" + (j+1) + ": { type: ArgumentType." + ((types[j] == "s" || types[j].slice(0,1) == "b" || pos != -1) ? "STRING, ": "NUMBER, ")
							+ "type2:'" + types[j] + "', ";
					var init:String = spec[3+j];
					if(pos == -1) {
						if((types[j] == "s" || types[j].slice(0,1) == "b") || isNaN(Number(init))) init = "'"+init+"'";
						_blocks += "defaultValue:" + init +" },\n";
					} else {
						if(!(types[j] == "s" || types[j].slice(0,1) == "b") && ext.values.hasOwnProperty(init)) {
							init = ext.values[init];
						}
						_blocks += "defaultValue:'" + init +"', menu: '" + args[j].slice(pos+1) + "' },\n";
					}
				}
				_blocks += "}},\n\n"
			}

			var ids:Array = new Array();
			var id:String;
			for(id in ext.menus)
				ids.push(id);

			for each(id in ids.sort()) {
				var values:Object = ext.menus[id];

	//	"noteJ1":["C2","D2","E2","F2","G2","A2","B2","C3","D3","E3","F3","G3","A3","B3",],

				menus += id + ": { acceptReporters: true, items: [";
				for(i=0;i<values.length;i++) {
					var en:String = values[i];
					if(!ext.values.hasOwnProperty(en)) {
						menus += "'" + en + "',";
					} else {
					//	{ text: 'ド4', value: 262 },
						if(i==0) menus += "\n";

						var val:String = en;
						val = ext.values[en];
						if(!ext.translators.ja.hasOwnProperty(en)) {
							menus += "{ text: '" + en + "', value: '" + val + "' },\n";
						} else {
							menus += "{ text: ['" + en + "','" + ext.translators.ja[en] + "'][this._locale], value: '" + val + "' },\n";
						}
					}

				}
				menus += "]},\n\n";
			}

			f = File.applicationDirectory.resolvePath("ext/libraries/Common/robot_pcmode.js.template");
			if(f==null || !f.exists)
				return false;
			var code:String = FileUtil.ReadString(f);

			if(ext.boardType.split(":")[1] == "esp32") {
				code = code.replace("/*ESP32*", "")
							.replace("*ESP32*/", "");
			}

			code = code.replace("// DEFINE\n", define)
						.replace("// FLASHES\n", flashes)
						.replace("// CONSTRUCTOR\n", ext.scratch3constructor)
						.replace("// BLOCKS\n", ext.scratch3blocks+"'---',\n"+_blocks)
						.replace("// MENUS\n", menus+ext.scratch3menus)
						.replace("// FUNCS\n", funcs+ext.scratch3funcs);

			f = new File(getNativePath("ext/scratch3/"+extNames[0]+".js"));
			FileUtil.WriteString(f, code);

			code = code.replace( /\n\/\/\*\n/g, "\n/*_\n")		// \n//*\n
						.replace(/\n\/\/\*\/\n/g,"\n_*/\n")		// \n//*/\n
						.replace(/\n\/\*\n/g,  "\n//*\n")		// \n/*\n
						.replace(/\n\*\/\n/g,  "\n//*/\n")		// \n*/\n
						.replace("var extName = '" + extNames[0], "var extName = '" + extNames[0]+'0');

			f = new File(getNativePath(ext.pcmodeFW+".update.js"));
			FileUtil.WriteString(f, code);

			return true;
		}
		
		
		public function jsonToCpp2():Boolean
		{
			var ext:ScratchExtension = Main.app.extensionManager.extensionByName();
		//	var f:File = new File(ext.pcmodeFW + ".ino.template");
			var f:File = File.applicationDirectory.resolvePath("ext/libraries/Common/robot_pcmode.ino.template");
			if(f==null || !f.exists)
				return false;
			var code:String = FileUtil.ReadString(f);

			code = code.replace("// HEADER\n", getProp(ext, "header"))
						.replace("// SETUP\n", getProp(ext, "setup"))
						.replace("// LOOP\n", getProp(ext, "loop"));

			var argTbl:String = "";
			var work:String = "";
			for(var i:int=0; i<ext.blockSpecsSize; i++) {
				var spec:Array = ext.blockSpecs[i];
				if(spec.length < 3){
					argTbl += "  {},\n";
					continue;
				}
				var obj:Object = spec[spec.length-1];
				if(!obj.hasOwnProperty("remote")) {
					argTbl += "  {},\n";
					continue;
				}
				var offset:int=0;
				var j:int;
				for(j=0; ; j++) {
					offset = spec[1].indexOf('%', offset);
					if(offset<0) break;
					offset++;
				}

				var argNum:int = obj.remote.length + ((spec[0]=='R' || spec[0]=='B') ? -1 : 0);
				if(spec.length-4 != argNum || j != argNum) {
					var msg:String = "error in argument num of \""+spec[2]+"\": BlockSpec="+j+", init="+(spec.length-4)+", remote="+argNum;

					var _dialog:DialogBox = new DialogBox();
					_dialog.addTitle(Translator.map('Error in json file'));
					_dialog.addButton(Translator.map('Close'), null);
					_dialog.setText(msg);
					_dialog.showOnStage(Main.app.stage);
					Main.app.scriptsPart.appendMessage(msg);
					return false;
				}

				argTbl += "  {";
				work += "case "+i.toString()+": ";

				var func:String = obj.func;
				for(j = 0; j<argNum; j++) {
					var getcmd:String = null;
					switch(obj.remote[j]) {
					case "B": getcmd = "getByte"; break;
					case "S": getcmd = "getShort"; break;
					case "L": getcmd = "getLong"; break;
					case "F": getcmd = "getFloat"; break;
					case "D": getcmd = "getDouble"; break;
					case "s": getcmd = "getString"; break;
					case "b": getcmd = "getBufLen"; break;
					case "b2": getcmd = "getBufLen2"; break;
					case "b3": getcmd = "getBufLen3"; break;
					}
					argTbl += "'"+obj.remote[j].slice(-1)+"',";
					func = func.replace(new RegExp("\\{"+j+"\\}", "g"), getcmd+"("+j.toString()+")");
				}

				switch(spec[0]) {
				case "w":
				//	case 1: remoconRobo_setRobot(getByte(0), getShort(1)); callOK(); break;
					work += func+"; callOK();";
					break;
				case "B":
				case "R":
				case "r":
				//	case 2: sendByte(pinMode(getByte(0), INPUT), digitalRead(getByte(0))); break;
					var setcmd:String = null;
					switch(obj.remote[obj.remote.length-1]) {
					case "B": setcmd = "sendByte"; break;
					case "S": setcmd = "sendShort"; break;
					case "L": setcmd = "sendLong"; break;
					case "F": setcmd = "sendFloat"; break;
					case "D": setcmd = "sendDouble"; break;
					case "s": setcmd = "sendString"; break;
					case "b": break;
					case "b2": break;
					case "b3": break;
					}
					work += (setcmd==null) ? func+";" : setcmd+"(("+func+"));";
					break;
				}
				argTbl += "},\n";
				work += " break;\n";
			}
			code = code.replace("// ARG_TYPES_TBL\n", argTbl);
			code = code.replace("// WORK\n", work);
			code = fixTabs(code);

			f = new File(getNativePath(ext.pcmodeFW + ".ino"));
			FileUtil.WriteString(f, code);
			return true;
		}

		// HACK: In Arduino mode, if you define a variable, set a variable, and perform IO operations on it，
		// This variable is set after the pinMode statement.
		// This can cause problems with uninitialized variables in the pinMode statement.
/*
		private function hackVaribleWithPinMode(originalCode:String):String
		{
			var lines:Array= originalCode.split("\n");
			var collectedPinModes:Array = [];
			var line:String;
			// collect all pinMode commands
			for(var i:int=0; i<lines.length; i++) {
				line = lines[i];
				if( line.indexOf("pinMode") != -1 || line.indexOf("// init pin") != -1 ) {
					var sliced:Array = lines.splice(i, 1);
					collectedPinModes = collectedPinModes.concat(sliced);
					i = i-1;
				}
			}
			
			if(collectedPinModes.length == 0){
				return originalCode;
			}
			
			// put pinMode command just before io commands
			for(i=0; i<lines.length; i++) {
				line = lines[i];
				if(line.indexOf("digitalWrite")!=-1 ||
					line.indexOf("digitalRead")!=-1 || 
					line.indexOf("pulseIn")!=-1 || 
					line.indexOf("if(")!=-1 || 
					line.indexOf("for(")!=-1 || 
					line.indexOf("while(")!=-1 || 
					line.indexOf("analogWrite")!=-1 || 
					line.indexOf("analogWrite")!=-1 || 
					line.indexOf("// write to")!=-1) {
					break;
				}
			}
			var linesBefore:Array = lines.splice(0, i);
			lines = linesBefore.concat(collectedPinModes, lines);
				
			var joinedLines:String = lines.join("\n");
			return joinedLines;
		}
*/
		private function getNativePath(url:String):String
		{
			return File.applicationDirectory.resolvePath(url).nativePath;
		}
		private function parseScripts(scripts:Object):Boolean
		{
			if(null == scripts){
				return false;
			}
			// scripts[0][2] = block配列 (関数名, 引数1, ..)
			var result:Boolean = false;
			for(var j:uint=0;j<scripts.length;j++){
				var scr:Object = scripts[j][2];
				if(scr[0][0]=="procDef"){
					addFunction(scr as Array);
					parseModules(scr);
					buildCodes();
				}
			}
			for(j=0;j<scripts.length;j++){
				scr = scripts[j][2];
			/*
				if(scr[0][0].indexOf("whenButtonPressed") > 0)
				{
					getCodeBlock(scr[0]);
				}
			*/
				if(scr[0][0].indexOf("runArduino") < 0){
					continue;	// １個目がrunArduinoでないときskip
				}

				if(!parseCodeBlocks(scr)){
					continue;
				}
				buildCodes();

				result = true;
				//break; // only the first entrance is parsed
			}
			if(_scratch!=null){
				_scratch.dispatchEvent(new RobotEvent(RobotEvent.CCODE_GOT,""));
			}
			return result;
		}
		private function buildCodes():void{
			buildDefine();
			buildSetup();
			ccode_setup+=ccode_setup_fun;
			ccode_setup_fun = "";
		}
		private function buildSetup():String{
			var modInitCode:String = "";
			for(var i:int=0;i<moduleList.length;i++){
				var m:Object = moduleList[i];
				var code:* = m["code"]["setup"];
				code = code is CodeObj?code.code: code;
				if(code!=""){
					if(ccode_setup.indexOf(code)==-1 && ccode_setup_fun.indexOf(code)==-1){
						ccode_setup+=code+"";
					}
				}
			}
			return modInitCode;
		}
		static private const varNamePattern:RegExp = /^[_A-Za-z][_A-Za-z0-9]*$/;
		static private function castVarName(name:String, isFunction:Boolean=false):String
		{
			if(varNamePattern.test(name)){
				return name;
			}
			var newName:String = isFunction ? "__func_" : "__var_";
			for(var i:int=0; i<name.length; ++i){
				newName += "_" + name.charCodeAt(i).toString();
			}
			return newName;
		}
		
		private function buildDefine():String{
			var modDefineCode:String = "";
			for(var i:int=0;i<varList.length;i++){
				var v:String = varList[i];
				var code:* = StringUtil.substitute("double {0};\n", castVarName(v));
				if(ccode_def.indexOf(code)==-1){
					ccode_def+=code;
				}
			}
			return modDefineCode;
		}
		
		private function buildFunctions():String{
			var funcCodes:String = "";
			for(var i:int=0;i<funcList.length;i++){
				var m:Object = funcList[i];
				var code:* = m["code"];
				code = code is CodeObj?code.code: code;
				if(code!=""){
					if(funcCodes.indexOf(code)==-1)
						funcCodes+=code+"\n";
				}
			}
			return funcCodes;
		}
		
		/****** *****************************
		 * compiler ralated functions 
		 * **********************************/
		
		// Open Arduino

		private var projectPath:String = "";
		public function openArduinoIDE(ccode:String):void
		{
			prepareProjectDir(ccode);
			openFW(projectPath+"/"+projectDocumentName+".ino");
		}
		
		private function prepareProjectDir(ccode:String):void{
			
			// get building direcotry ready
			var workdir:File = File.applicationStorageDirectory.resolvePath("scratchTemp");
			if(!workdir.exists){
				workdir.createDirectory();
			}
			if(!workdir.exists){
				return;
			}
			// copy firmware directory
			workdir = workdir.resolvePath(projectDocumentName);
			var projCpp:File = File.applicationStorageDirectory.resolvePath("scratchTemp/"+projectDocumentName+"/"+projectDocumentName+".ino")
			Main.app.track("projCpp:"+projCpp.nativePath);
			var outStream:FileStream = new FileStream();
			outStream.open(projCpp, FileMode.WRITE);
			outStream.writeUTFBytes(ccode);
			outStream.close();
			projectPath = workdir.url;
			Main.app.track("projectPath:"+projectPath);
		}
		
		private function get projectDocumentName():String{
			var now:Date = new Date;
			var pName:String = Main.app.projectName().split(" ").join("").split("(").join("").split(")").join("");
			//用正则表达式来过滤非法字符
			var reg:RegExp = /[^A-z0-9]|^_/g;
			pName = pName.replace(reg,"_");

			var _projectDocumentName:String = "project_"+pName+ (now.getMonth()+"_"+now.getDay());
			if(_projectDocumentName=="project_"){
				_projectDocumentName = "project";
			}
			return _projectDocumentName;
		}
/*
		public function buildPcmode():void
		{
			if(!jsonToCpp2()) return;
			buildFW(Main.app.extensionManager.extensionByName().pcmodeFW + ".ino");
		}
*/
		public function openPcmode():void
		{
			jsonToJs();
			if(!jsonToCpp2()) return;
			openFW(Main.app.extensionManager.extensionByName().pcmodeFW + ".ino");
		}
/*
		public function buildNormal():void
		{
			buildFW(Main.app.extensionManager.extensionByName().normalFW + ".ino");
		}
*/
		public function openNormal():void
		{
			openFW(Main.app.extensionManager.extensionByName().normalFW + ".ino");
		}

		private function getArduino():File
		{
			if(ApplicationManager.sharedManager().system == ApplicationManager.MAC_OS)
				return File.applicationDirectory.resolvePath("Arduino/Arduino.app/Contents/MacOS/Arduino");
			else
				return File.applicationDirectory.resolvePath("Arduino/arduino.exe");
		}

		private function getArduinoDebug():File
		{
			if(ApplicationManager.sharedManager().system == ApplicationManager.MAC_OS)
				return File.applicationDirectory.resolvePath("Arduino/Arduino.app/Contents/MacOS/Arduino");
			else
				return File.applicationDirectory.resolvePath("Arduino/arduino_debug.exe");
		}

		private function openFW(filePath:String):void
		{
			if(!File.applicationDirectory.resolvePath(filePath).exists)
				return;
			
			var openFilePath:String = filePath;

			var tmps:Array = filePath.split("/");
			tmps.pop();
			var buildPath:String = tmps.join("/");

			var ext:ScratchExtension = Main.app.extensionManager.extensionByName();
			var argList:Vector.<String> = Vector.<String>([
				"--board", ext.boardType,
				"--port", ConnectionManager.sharedManager().selectPort,
				"--pref", "build.path="+getNativePath(buildPath+"/build")]);
			for(var i:int = 0; i < ext.prefs.length; i++)
				argList.push("--pref", ext.prefs[i]);
			argList.push("--save-prefs");

			if(!getArduinoDebug().exists) {
				var dialog:DialogBox = new DialogBox();
	 			dialog.addTitle(Translator.map('TuKuRutch package Error'));
				dialog.setText('src.ino and xx.js have been generated. Please open ext/libraries/xx/src with ArduinoIDE.');
				dialog.addButton(Translator.map('Close'), null);
				dialog.showOnStage(Main.app.stage);
				return;
			}

			Main.app.scriptsPart.appendMessage(getArduinoDebug().nativePath + " " + argList.join(" "));
			
			var info:NativeProcessStartupInfo = new NativeProcessStartupInfo();
			info.executable = getArduinoDebug();
			info.arguments = argList;

			var process:NativeProcess = new NativeProcess();
			process.addEventListener(NativeProcessExitEvent.EXIT, __onSetupExit);
			process.start(info);

			function __onSetupExit(event:NativeProcessExitEvent):void
			{
				Main.app.track("Process exited with "+event.exitCode);
				if(event.exitCode != 0) return;

				var info:NativeProcessStartupInfo =new NativeProcessStartupInfo();
				info.executable = getArduino();
				info.arguments = Vector.<String>([getNativePath(openFilePath)]);

				process = new NativeProcess();
				process.addEventListener(ProgressEvent.STANDARD_OUTPUT_DATA, function(e:ProgressEvent):void{});
				process.addEventListener(ProgressEvent.STANDARD_ERROR_DATA, function(e:ProgressEvent):void{});
				process.addEventListener(NativeProcessExitEvent.EXIT, function(e:NativeProcessExitEvent):void{});
				process.start(info);
				return;
			}
		}

		// build firmware

		private function buildFW(filePath:String):void
		{
			var buildFilePath:String = filePath;

			var _dialog:DialogBox = new DialogBox();
 			_dialog.addTitle(Translator.map('Start Building'));
		//	_dialog.addButton(Translator.map('Close'), null);
			_dialog.setText(Translator.map('Building'));
			_dialog.showOnStage(Main.app.stage);

			var tmps:Array = filePath.split("/");
			tmps.pop();
			var buildPath:String = tmps.join("/");

			var ext:ScratchExtension = Main.app.extensionManager.extensionByName();
			var argList:Vector.<String> = Vector.<String>([
				"--verify", "--board", ext.boardType,
			//	"--port", ConnectionManager.sharedManager().selectPort,
				"--verbose-upload",	//	"--verbose", 
				"--pref", "build.path="+getNativePath(buildPath+"/build")]);
			for(var i:int = 0; i < ext.prefs.length; i++)
				argList.push("--pref", ext.prefs[i]);
			argList.push(getNativePath(filePath));

			Main.app.scriptsPart.appendMessage(getArduinoDebug().nativePath + " " + argList.join(" "));
			
			var info:NativeProcessStartupInfo = new NativeProcessStartupInfo();
			info.executable = getArduinoDebug();
			info.arguments = argList;

			var process:NativeProcess = new NativeProcess();
			process.addEventListener(ProgressEvent.STANDARD_OUTPUT_DATA, __onData);
			process.addEventListener(ProgressEvent.STANDARD_ERROR_DATA, __onErrorData);
			process.addEventListener(NativeProcessExitEvent.EXIT, __onBuildExit);
			process.start(info);

			function __onBuildExit(event:NativeProcessExitEvent):void
			{
				isUploading = false;
				_dialog.addButton(Translator.map('Close'), null);
				if(event.exitCode == 0){
					_dialog.setText(Translator.map('Build Finish'));

					var boards:Array = Main.app.extensionManager.extensionByName().boardType.split(":");
					var extensionDes:String = getHexFilename(boards);
					var extensionSrc:String = ".hex";
					switch(boards[1]) {
					case "esp32":
						extensionSrc = ".bin";
						break;
					}
					var tmps:Array = buildFilePath.split("/");
					var fileName:String = tmps.pop();
					var buildPath:String = tmps.join("/");

					extensionSrc = buildPath+"/build/"+fileName+extensionSrc;
					extensionDes = buildPath+"/"      +fileName+extensionDes;
					Main.app.track("copy "+extensionSrc+" to "+extensionDes);
					var desFile:File = new File(getNativePath(extensionDes));	// for security error
					File.applicationDirectory.resolvePath(extensionSrc).copyTo(desFile, true);
				}else{
					_dialog.setText(Translator.map('Build Failed'));
				}
				ConnectionManager.sharedManager().update();
				//ConnectionManager.sharedManager().reopen();
			}
		}

		public function getHexFilename(boards:Array):String
		{
			switch(boards[1]) {
			case "avr":
			default:
				return ".standard.hex";
			case "samd":	// board=mzero_bl
				return ".arduino_mzero.hex";
			case "esp32":
				var reg:RegExp = /-/g;
				return "."+boards[2].replace(reg,"_")+".bin";		// m5stack-core-esp32 -> m5stack_core_esp32
			}
		}

		// Upload to Arduino
		
		public var isUploading:Boolean = false;
		public function UploadToArduino(ccode:String):String
		{
			if(isUploading){
				return "uploading";
			}
			// get building direcotry ready
			var workdir:File = File.applicationStorageDirectory.resolvePath("scratchTemp")
			if(!workdir.exists){
				workdir.createDirectory();
			}
			
			if(!workdir.exists){
				return "workdir not exists";
			}
			// copy firmware directory
			workdir = workdir.resolvePath(projectDocumentName);
			var projCpp:File = File.applicationStorageDirectory.resolvePath("scratchTemp/"+projectDocumentName+"/"+projectDocumentName+".ino");
			var outStream:FileStream = new FileStream();
			outStream.open(projCpp, FileMode.WRITE);
			outStream.writeUTFBytes(ccode);
			outStream.close();
			ConnectionManager.sharedManager().onClose();
			uploadFW(projCpp.url);
			isUploading = true;
			return "";
		}

		private function uploadFW(filePath:String):void
		{
			var _dialog:DialogBox = new DialogBox();
 			_dialog.addTitle(Translator.map('Start Uploading'));
		//	_dialog.addButton(Translator.map('Close'), null);
			_dialog.setText(Translator.map('Uploading'));
			_dialog.showOnStage(Main.app.stage);

			var tmps:Array = filePath.split("/");
			tmps.pop();
			var buildPath:String = tmps.join("/");

			var ext:ScratchExtension = Main.app.extensionManager.extensionByName();
			var argList:Vector.<String> = Vector.<String>([
				"--upload", "--board", ext.boardType,
				"--port", ConnectionManager.sharedManager().selectPort,
				"--verbose-upload",	//	"--verbose", 
				"--pref", "build.path="+getNativePath(buildPath+"/build")]);
			for(var i:int = 0; i < ext.prefs.length; i++)
				argList.push("--pref", ext.prefs[i]);
			argList.push(getNativePath(filePath));

			Main.app.scriptsPart.appendMessage(getArduinoDebug().nativePath + " " + argList.join(" "));
			
			var info:NativeProcessStartupInfo = new NativeProcessStartupInfo();
			info.executable = getArduinoDebug();
			info.arguments = argList;

			var process:NativeProcess = new NativeProcess();
			process.addEventListener(ProgressEvent.STANDARD_OUTPUT_DATA, __onData);
			process.addEventListener(ProgressEvent.STANDARD_ERROR_DATA, __onErrorData);
			process.addEventListener(NativeProcessExitEvent.EXIT, __onUploadExit);
			process.start(info);
		
			function __onUploadExit(event:NativeProcessExitEvent):void
			{
				//ext.docPath+"/arduinoBuild
				isUploading = false;
				_dialog.addButton(Translator.map('Close'), null);
				if(event.exitCode == 0){
					_dialog.setText(Translator.map('Upload Finish'));
				}else{
					_dialog.setText(Translator.map('Upload Failed'));
				}
				ConnectionManager.sharedManager().update();
				//ConnectionManager.sharedManager().reopen();
			}
		}
		
		private function __appendRawMessage(info:String):void
		{
			var i:int;
			i = info.indexOf("DEBUG StatusLogger ");
			if(i == 0) return;
			if(i > 0) info = info.substr(0,i);

			i = info.indexOf("TRACE StatusLogger ");
			if(i == 0) return;
			if(i > 0) info = info.substr(0,i);

			i = info.indexOf("INFO StatusLogger ");
			if(i == 0) return;
			if(i > 0) info = info.substr(0,i);

			i = info.indexOf(" INFO c.a.u.");
			if(i >= 0) return;

			i = info.indexOf(" WARN p.a.h.");
			if(i >= 0) return;

			Main.app.scriptsPart.appendRawMessage(info);
		}
		
		private function __onData(event:ProgressEvent):void
		{
			var process:NativeProcess = event.target as NativeProcess;
			var info:String = process.standardOutput.readMultiByte(process.standardOutput.bytesAvailable, "utf-8");//"gb2312");
			__appendRawMessage(info);
		}
		
		private function __onErrorData(event:ProgressEvent):void
		{
			var process:NativeProcess = event.target as NativeProcess;
			var info:String = process.standardError.readMultiByte(process.standardError.bytesAvailable, "utf-8");//"gb2312");
			__appendRawMessage(info);
		}
	}
}