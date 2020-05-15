package cc.makeblock.interpreter
{
	import blockly.runtime.FunctionProvider;
	import blockly.runtime.Thread;
	import blockly.util.FunctionProviderHelper;
	
	import extensions.ScratchExtension;
	import extensions.ConnectionManager;
	
	public class ArduinoFunctionProvider extends FunctionProvider
	{
		public function ArduinoFunctionProvider()
		{
			FunctionProviderHelper.InitMath(this);
			FunctionSounds.Init(this);
			new FunctionList().addPrimsTo(this);
			new FunctionLooks().addPrimsTo(this);
			new FunctionMotionAndPen().addPrimsTo(this);
			new Primitives().addPrimsTo(this);
			new FunctionSensing().addPrimsTo(this);
			new FunctionVideoMotion().addPrimsTo(this);
			PrimInit.Init(this);
		}

		override protected function onCallUnregisteredFunction(thread:Thread, name:String, argList:Array, retCount:int):void
		{
			var index:int = name.indexOf(".");
			if(index < 0){
				if(name.indexOf("when") < 0){
					super.onCallUnregisteredFunction(thread, name, argList, retCount);
				}
				return;
			}
			var extName:String = name.slice(0, index);
			var opName:String = name.slice(index+1);
			var ext:ScratchExtension = Main.app.extensionManager.extensionByName();//extName);
			if(null == ext){
				thread.interrupt();
				return;
			}
			if(!ext.useSerial){
				thread.push(ext.getStateVar(opName));
			}else if(ConnectionManager.sharedManager().isConnected){	// debug
				RemoteCallMgr.Instance.call(thread, opName, argList, ext, retCount);
			}else if(retCount > 0){
				thread.push(0);
			}
		}
	}
}