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
	import flash.system.Capabilities;
	import flash.utils.getQualifiedClassName;
	
	import blocks.Block;
	import blocks.BlockIO;
	
	import cc.makeblock.mbot.util.PopupUtil;
	import cc.makeblock.mbot.util.StringUtil;
	import cc.makeblock.util.FileUtil;
	
	import translation.Translator;
	
	import util.ApplicationManager;
	import util.JSON;
	import util.LogManager;

	public class ArduinoManager extends EventDispatcher
	{
		private static var _instance:ArduinoManager;
		public var _scratch:Main;
		
		public var isUploading:Boolean = false;
		
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
		private var arduinoPath:String;
		private var projectPath:String = "";
		
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
				return (StringUtil.substitute("{0} = {1};\n",castVarName(varName),varValue.type=="obj"?varValue.code.code:varValue.code));
			}else{
				return (StringUtil.substitute("{0} = {1};\n",castVarName(varName),varValue is CodeObj?varValue.code:varValue));
			}
		}
		private function parseDelay(fun:Object):String{
			var cBlk:CodeBlock=getCodeBlock(fun[1]);
			var funcode:String=(StringUtil.substitute("_delay({0});\n",cBlk.type=="obj"?cBlk.code.code:cBlk.code));
			return funcode;
		}
		private function parseDoRepeat(blk:Object):String{
			var initCode:CodeBlock = getCodeBlock(blk[1]);
			var repeatCode:String=StringUtil.substitute("for(int __i__=0;__i__<{0};++__i__)\n{\n",initCode.type=="obj"?initCode.code.code:initCode.code);
			if(blk[2]!=null){
				for(var i:int=0;i<blk[2].length;i++){
					var b:Object = blk[2][i];
					var cBlk:CodeBlock=getCodeBlock(b);
					repeatCode+=cBlk.type=="obj"?cBlk.code.code:cBlk.code;
				}
			}
			repeatCode+="}\n";
			return repeatCode;
		}
		private function parseDoWaitUntil(blk:Object):String{
			var initCode:CodeBlock = getCodeBlock(blk[1]);
			var untilCode:String=StringUtil.substitute("while(!({0}))\n{\n_loop();\n}\n",initCode.type=="obj"?initCode.code.code:initCode.code);
			return (untilCode);
		}
		private function parseDoUntil(blk:Object):String{
			var initCode:CodeBlock = getCodeBlock(blk[1]);
			var untilCode:String=StringUtil.substitute("while(!({0}))\n{\n_loop();\n",initCode.type=="obj"?initCode.code.code:initCode.code);
			if(blk[2]!=null){
				for(var i:int=0;i<blk[2].length;i++){
					var b:Object = blk[2][i];
					var cBlk:CodeBlock=getCodeBlock(b);
					untilCode+=cBlk.type=="obj"?cBlk.code.code:cBlk.code;
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
				vars += (params[i]=='n'?("double"):(params[i]=='s'?"String":(params[i]=='b'?"boolean":"")))+" "+castVarName(blks[0][2][i-1].split(" ").join("_"))+(i<params.length-1?", ":"");
			}
			var defFunc:String = "void "+castVarName(params[0], true)+"("+vars+");\n";
			if(ccode_def.indexOf(defFunc)==-1){
				ccode_def+=defFunc;
			}
			var funcCode:String = "void "+castVarName(params[0], true)+"("+vars+")\n{\n";
			for(i=0;i<blks.length;i++){
				if(i>0){
					
					var b:CodeBlock = getCodeBlock(blks[i],blks[0][2]);
					var code:String = (b.type=="obj"?b.code.code:b.code);
					funcCode+=code+"\n";
				}
			}
			funcCode+="}\n";
			funcList.push({name:funcName,code:funcCode});
		}
		private function parseIfElse(blk:Object):String{
			var codeIfElse:String = "";
			var logiccode:CodeBlock = getCodeBlock(blk[1]);
			codeIfElse+=StringUtil.substitute("if({0}){\n",logiccode.type=="obj"?logiccode.code.code:logiccode.code);
			if(blk[2]!=null){
				for(var i:int=0;i<blk[2].length;i++){
					var b:CodeBlock = getCodeBlock(blk[2][i]);
					var ifcode:String=(b.type=="obj"?b.code.code:b.code)+"";
					codeIfElse+=ifcode
				}
			}
			codeIfElse+="}else{\n";
			if(blk[3]!=null){
				for(i=0;i<blk[3].length;i++){
					b = getCodeBlock(blk[3][i]);
					var elsecode:String=(b.type=="obj"?b.code.code:b.code)+"";
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
							var ifcode:String=(b.type=="obj"?b.code.code:b.code)+"";
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
			if(blk[1]=="10 ^"){
				return StringUtil.substitute("pow(10,{0})",cBlk.code);
			}else if(blk[1]=="e ^"){
				return StringUtil.substitute("exp({0})",cBlk.code);
			}else if(blk[1]=="ceiling"){
				return StringUtil.substitute("ceil({0})",cBlk.code);
			}else if(blk[1]=="log"){
				return StringUtil.substitute("log10({0})",cBlk.code);
			}else if(blk[1]=="ln"){
				return StringUtil.substitute("log({0})",cBlk.code);
			}
			
			return StringUtil.substitute("{0}({1})",getCodeBlock(blk[1]).code,cBlk.code).split("sin(").join("sin(angle_rad*").split("cos(").join("cos(angle_rad*").split("tan(").join("tan(angle_rad*");
		}
		private function appendFun(funcode:*):void{
			//			if (c!="\n" && c!="}")
			//funcode+=";\n"
			var allowAdd:Boolean = funcode is CodeObj;
			funcode = funcode is CodeObj?funcode.code:funcode;
			
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
		
		private function getCodeBlock(blk:Object,params:Array=null):CodeBlock{
			var code:CodeObj;
			var codeBlock:CodeBlock = new CodeBlock;
			if(blk==null||blk==""){
				codeBlock.type = "number";
				codeBlock.code = "0";
				return codeBlock;
			}
			if(!(blk is Array)){
				codeBlock.code = ""+blk;
				codeBlock.type = isNaN(Number(blk))?"string":"number";
				return codeBlock;
			}
			if(blk.length==0){
				codeBlock.type = "string";
				codeBlock.code = "";
				return codeBlock;
			}else if(blk.length==16){
				codeBlock.type = "array";
				codeBlock.code = blk;
				return codeBlock;
			}
			if(mathOp.indexOf(blk[0])>=0){
				codeBlock.type = "obj";
				codeBlock.code = parseMath(blk);
				return codeBlock;
			}
			else if(blk[0]=="readVariable"){
				codeBlock.type = "obj";
				codeBlock.code = parseVarRead(blk);
				return codeBlock;
			}
			else if(blk[0]=="initVar:to:"){
				codeBlock.type = "obj";
				codeBlock.code = null;
				var tmpCodeBlock:Object = {code:{setup:parseVarSet(blk)}};
				moduleList.push(tmpCodeBlock);
				return codeBlock;
			}
			else if(blk[0]=="setVar:to:"){
				codeBlock.type = "string";
				codeBlock.code = parseVarSet(blk);
				return codeBlock;
			}
			else if(blk[0]=="wait:elapsed:from:"){
				codeBlock.type = "string";
				codeBlock.code = parseDelay(blk);
				return codeBlock;
			}
			else if(blk[0]=="doIfElse"){
				codeBlock.type = "string";
				codeBlock.code = parseIfElse(blk);
				return codeBlock;
			}
			else if(blk[0]=="doIf"){
				codeBlock.type = "string";
				codeBlock.code = parseIf(blk);
				return codeBlock;
			}
			else if(blk[0]=="doRepeat"){
				codeBlock.type = "string";
				codeBlock.code = parseDoRepeat(blk);
				return codeBlock;
			}/*else if(blk[0]=="doForever"){
				codeBlock.type = "string";
				codeBlock.code = parseForever(blk);
				return codeBlock;
			}*/else if(blk[0]=="doWaitUntil"){
				codeBlock.type = "string";
				codeBlock.code = parseDoWaitUntil(blk);
				return codeBlock;
			}else if(blk[0]=="doUntil"){
				codeBlock.type = "string";
				codeBlock.code = parseDoUntil(blk);
				return codeBlock;
			}else if(blk[0]=="call"){
				codeBlock.type = "obj";//修复新建的模块指令函数，无法重复调用
				codeBlock.code = new CodeObj(parseCall(blk));
				return codeBlock;
			}else if(blk[0]=="randomFrom:to:"){
				codeBlock.type = "number";
				//as same as scratch, include max value
				codeBlock.code = StringUtil.substitute("random({0},({1})+1)", getCodeBlock(blk[1]).code, getCodeBlock(blk[2]).code);
				return codeBlock;
			}else if(blk[0]=="computeFunction:of:"){
				codeBlock.type = "number";
				codeBlock.code = parseComputeFunction(blk);
				return codeBlock;
			}else if(blk[0]=="concatenate:with:"){
				var s1:CodeBlock = getCodeBlock(blk[1]);
				var s2:CodeBlock = getCodeBlock(blk[2]);
				codeBlock.type = "obj";
				codeBlock.code = new CodeObj(StringUtil.substitute("{0}+{1}", (s1.type=="obj")?s1.code.code:"String(\""+s1.code+"\")", (s2.type=="obj")?s2.code.code:"String(\""+s2.code+"\")"));
				return codeBlock;
			}else if(blk[0]=="letter:of:"){
				s2 = getCodeBlock(blk[2]);
				codeBlock.type = "obj";
				codeBlock.code = new CodeObj(StringUtil.substitute("{1}.charAt({0}-1)", getCodeBlock(blk[1]).code, (s2.type=="obj")?"String("+s2.code.code+")":"String(\""+s2.code+"\")"));
				return codeBlock;
			}else if(blk[0]=="castDigitToString:"){
				codeBlock.type = "obj";
				codeBlock.code = new CodeObj(StringUtil.substitute('String({0})', getCodeBlock(blk[1]).code));
				return codeBlock;
			}else if(blk[0]=="stringLength:"){
				s1 = getCodeBlock(blk[1]);
				codeBlock.type = "obj";
				codeBlock.code = new CodeObj(StringUtil.substitute("String({0}).length()", (s1.type != "obj")?"\""+s1.code+"\"":s1.code.code));
				return codeBlock;
			}else if(blk[0]=="changeVar:by:"){
				codeBlock.type = "string";
				codeBlock.code = StringUtil.substitute("{0} += {1};\n", getCodeBlock(castVarName(blk[1])).code, getCodeBlock(blk[2]).code);
				return codeBlock;
			}
			else{
				var objs:Array = Main.app.extensionManager.specForCmd(blk[0]);
				if(objs!=null){
					var obj:Object = objs[objs.length-1];	// spec[1]:"play tone ..", spec[0]:"w", extensionsCategory:20, prefix+spec[2]:"remoconRobo.runBuzzerJ2", spec.slice(3):(初期値+obj)
					obj = obj[obj.length-1];				// 初期値, .. obj
					if(typeof obj=="object"){
						var ext:ScratchExtension = Main.app.extensionManager.extensionByName();//blk[0].split(".")[0]);
						var codeObj:Object = {code:{setup:substitute(getProp(obj,'setup'), blk as Array, ext),
													func :substitute(getProp(obj,'func'),  blk as Array, ext)}};
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
				if(b.op=="getParam"){
					codeBlock.type = "number";
					codeBlock.code = castVarName(b.spec.split(" ").join("_"));
					return codeBlock;
				}
				if(b.op=="procDef"){
					return codeBlock;
				}
				unknownBlocks.push(b);
				hasUnknownCode = true;
				codeBlock.type = "string";
				codeBlock.code = StringUtil.substitute("//unknow {0}{1}",blk[0],b.type=='r'?"":"\n");
				return codeBlock;
			}
			codeBlock.type = "obj";
			codeBlock.code = code;
			return codeBlock;
		}
		private function getProp(obj:Object, key:String):String{
			return obj.hasOwnProperty(key) ? obj[key] : "";
		}
		// デファインをext.valuesで展開し、"remoconRobo_tone({0},{1});\n" の{0},{1}を展開
		private function substitute(str:String, params:Array, ext:ScratchExtension=null, offset:uint = 1):String{
			for(var i:uint=0;i<params.length-offset;i++){
				var o:CodeBlock = getCodeBlock(params[i+offset]);
				var v:*;
			/*
				//满足下面的条件则不作字符替换处理
				if(str.indexOf("ir.sendString")>-1 || (str.indexOf(".drawStr(")>-1 && i==3))
				{
					v = o.code;
				}
				else
			*/
				{
					if(o.type!="string")
						v = null;
					else if(ext.values[o.code]!=undefined)
						v = ext.values[o.code];
					else
						v = o.code;
				}
				var s:CodeBlock = new CodeBlock();
				if(ext==null || v==null || v==undefined){
					s = getCodeBlock(params[i+offset]);
					s.type = (s.type=="obj" && s.code.type!="code")?"string":"number";
				}else{
					s.type = isNaN(Number(v))?"string":"number";
					s.code = v;
				}
				if((s.code==""||s.code==" ") && s.code!=0 && s.type=="number"){
					s.type = "string";
				}
			/*
				if(str.indexOf(".drawStr(")>-1){
					if(i==3 && s.type=="number"){
						if(s.code is String){
							s.type = "string";
						}else if(s.code is CodeObj){
							str = str.split("{"+i+"}").join("String("+s.code.code+").c_str()");
							continue;
						}
					}
				}else if(str.indexOf("ir.sendString(") == 0){
					if(s.type=="number" && s.code is String){
						s.type = "string";
					}
				}
				// 通信モジュールの=記号が使用されている場合、数値も比較のために文字列に変換されます。そうでない場合、エラーが報告されます
				if(str.indexOf("se.equalString")>-1)
				{
					str = str.split("{"+i+"}").join((s.type=="string"||!isNaN(Number(s.code)))?('"'+s.code+'"'):((s.type=="number")?s.code:s.code.code));
				}
				else
			*/
				{
					str = str.split("{"+i+"}").join((s.type=="string")?('"'+s.code+'"'):((s.type=="number")?s.code:s.code.code));
				}
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
Serial.println("Normal: " mVersion);
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
		
		public function jsonToCpp2():void
		{
			var ext:ScratchExtension = Main.app.extensionManager.extensionByName();
		//	var f:File = new File(File.applicationDirectory.nativePath + "/ext/firmware/hex/robot_pcmode/robot_pcmode.ino.template");
			var f:File = new File(ext.docPath + ext.pcmodeFW + ".ino.template");
			if(f==null || !f.exists)
				return;
			var code:String = FileUtil.ReadString(f);

			code = code.replace("// HEADER", getProp(ext, "header"))
						.replace("// SETUP", getProp(ext, "setup"))
						.replace("// LOOP", getProp(ext, "loop"));

			var work:String = "";
			for(var i:int=0; i<ext.blockSpecs.length; i++) {
				var spec:Array = ext.blockSpecs[i];
				if(spec.length < 3){
					continue;
				}
				var obj:Object = spec[spec.length-1];
				if(!obj.hasOwnProperty("remote")) continue;
				var getcmds:Array = [];
				var setcmd:String;
				var offset:int=0;
				var j:int;
				for(j=0; j<obj.remote.length; j++) {
					switch(obj.remote[j]) {
					case "B": getcmds[j] = "getByte("+offset.toString()+")";   offset+=1; setcmd="sendByte"; break;
					case "S": getcmds[j] = "getShort("+offset.toString()+")";  offset+=2; setcmd="sendShort"; break;
					case "L": getcmds[j] = "getLong("+offset.toString()+")";   offset+=4; setcmd="sendLong"; break;
					case "F": getcmds[j] = "getFloat("+offset.toString()+")";  offset+=4; setcmd="sendFloat"; break;
					case "D": getcmds[j] = "getDouble("+offset.toString()+")"; offset+=8; setcmd="sendDouble"; break;
					case "s": getcmds[j] = "getString("+offset.toString()+")"; offset+=8; setcmd="sendString"; break;
					}
				}
				var tmp:String = obj.func;
				switch(spec[0]) {
				case "w":
				//	case CMD_ROBOT: remoconRobo_setRobot(getByte(0), getShort(1)); callOK(); break;
					for(j = 0; j<obj.remote.length; j++)
						tmp = tmp.replace(new RegExp("\\{"+j+"\\}", "g"), getcmds[j]);
					work += "case " + i.toString() + ": " + tmp + "; callOK(); break;\n";
					break;
				case "B":
				case "R":
				//	case CMD_DIGITAL: sendByte(pinMode(getByte(0), INPUT), digitalRead(getByte(0))); break;
					for(j = 0; j<obj.remote.length-1; j++)
						tmp = tmp.replace(new RegExp("\\{"+j+"\\}", "g"), getcmds[j]);
					work += "case " + i.toString() + ": " + setcmd + "((" + tmp + ")); break;\n";
					break;
				}
			}
			code = code.replace("// WORK\n", work);
			code = fixTabs(code);

		//	f = new File(File.applicationDirectory.nativePath + "/ext/libraries/robot/robot_pcmode/robot_pcmode.ino");
			f = new File(url2nativePath(ext.docPath + ext.pcmodeFW + ".ino"));
			FileUtil.WriteString(f, code);
			return;
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
		private function url2nativePath(url:String):String
		{
			var f:File = new File(url);
			return f.nativePath;
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
				code = code is CodeObj?code.code:code;
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
				var code:* = StringUtil.substitute("double {0};\n" ,castVarName(v));
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
				code = code is CodeObj?code.code:code;
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
		
	//	private var numOfSuccess:uint = 0;
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
			LogManager.sharedManager().log("projCpp:"+projCpp.nativePath);
			var outStream:FileStream = new FileStream();
			outStream.open(projCpp, FileMode.WRITE);
			outStream.writeUTFBytes(ccode);
			outStream.close();
			projectPath = workdir.nativePath;
			LogManager.sharedManager().log("projectPath:"+projectPath);
		}
		
		private var compileErr:Boolean = false;
		private var _projectDocumentName:String = "";
		private function get projectDocumentName():String{
			var now:Date = new Date;
			var pName:String = Main.app.projectName().split(" ").join("").split("(").join("").split(")").join("");
			//用正则表达式来过滤非法字符
			var reg:RegExp = /[^A-z0-9]|^_/g;
			pName = pName.replace(reg,"_");
			_projectDocumentName = "project_"+pName+ (now.getMonth()+"_"+now.getDay());
			if(_projectDocumentName=="project_"){
				_projectDocumentName = "project";
			}
			return _projectDocumentName;
		}
		public function buildAll(ccode:String):String
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
			UploaderEx.Instance.upload(projCpp.nativePath);
			isUploading = true;
			return "";
		}
		
		
		public function openArduinoIDE(ccode:String):String{
			prepareProjectDir(ccode);
			var file:File;
			if(ApplicationManager.sharedManager().system==ApplicationManager.WINDOWS){
				file = new File(arduinoInstallPath+"/arduino.exe");
			}else{
				file = new File(arduinoInstallPath+"/../MacOS/Arduino");
			}
			
			var processArgs:Vector.<String> = new Vector.<String>();
			//trace(contents[i].name, contents[i].size);
			var nativeProcessStartupInfo:NativeProcessStartupInfo =new NativeProcessStartupInfo();
			nativeProcessStartupInfo.executable = file;
			processArgs.push(projectPath+"/"+projectDocumentName+".ino");
			nativeProcessStartupInfo.arguments = processArgs;
			process = new NativeProcess();
			process.addEventListener(ProgressEvent.STANDARD_OUTPUT_DATA, function(e:ProgressEvent):void{});
			process.addEventListener(ProgressEvent.STANDARD_ERROR_DATA, function(e:ProgressEvent):void{});
			process.addEventListener(NativeProcessExitEvent.EXIT, function(e:NativeProcessExitEvent):void{});
			process.start(nativeProcessStartupInfo);
			return "";
		}
		public function openArduinoIDE2():void
		{
			jsonToCpp2();

			var ext:ScratchExtension = Main.app.extensionManager.extensionByName();
			var file:File;
			if(ApplicationManager.sharedManager().system==ApplicationManager.WINDOWS){
				file = new File(arduinoInstallPath+"/arduino.exe");
			}else{
				file = new File(arduinoInstallPath+"/../MacOS/Arduino");
			}
			var processArgs:Vector.<String> = new Vector.<String>();
			var nativeProcessStartupInfo:NativeProcessStartupInfo =new NativeProcessStartupInfo();
			nativeProcessStartupInfo.executable = file;
			processArgs.push(url2nativePath(ext.docPath + ext.pcmodeFW + ".ino"));
			nativeProcessStartupInfo.arguments = processArgs;
			process = new NativeProcess();
			process.addEventListener(ProgressEvent.STANDARD_OUTPUT_DATA, function(e:ProgressEvent):void{});
			process.addEventListener(ProgressEvent.STANDARD_ERROR_DATA, function(e:ProgressEvent):void{});
			process.addEventListener(NativeProcessExitEvent.EXIT, function(e:NativeProcessExitEvent):void{});
			process.start(nativeProcessStartupInfo);
			return;
		}
		private function get arduinoInstallPath():String{
			if(null == arduinoPath){
				if(Capabilities.os.indexOf("Windows") == 0){
					arduinoPath = File.applicationDirectory.resolvePath("Arduino").nativePath;
				}else{
					arduinoPath = File.applicationDirectory.resolvePath("Arduino/Arduino.app/Contents/Java").nativePath;
				}
			}
			return arduinoPath;
		}
	}
}