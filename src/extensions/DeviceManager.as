package extensions
{
	import util.SharedObjectManager;

	public class DeviceManager
	{
		private static var _instance:DeviceManager;
		private var _device:String = "";
		private var _board:String = "";
		private var _name:String = "";
		public function DeviceManager()
		{
			onSelectBoard("remoconRobo");
		}
		public static function sharedManager():DeviceManager{
			if(_instance==null){
				_instance = new DeviceManager;
			}
			return _instance;
		}
		private function set board(value:String):void
		{
			_board = value;
			var tempList:Array = _board.split("_");
			_device = tempList[tempList.length-1];
		}
		public function onSelectBoard(value:String):void{
			if(_board == value){
				return;
			}
			this.board = value;
		/*
			var oldBoard:String = SharedObjectManager.sharedManager().getObject("board");
			SharedObjectManager.sharedManager().setObject("board",_board);
			if(_board=="mbot_uno"){
				MBlock.app.extensionManager.singleSelectExtension("FamilyDay");//"mBot");
			}else if(_board.indexOf("arduino")>-1){
				MBlock.app.extensionManager.singleSelectExtension("Arduino");
			}
		*/
			MBlock.app.extensionManager.singleSelectExtension("remoconRobo");
			MBlock.app.topBarPart.setBoardTitle();
		}
		public function checkCurrentBoard(board:String):Boolean{
			return _board==board;
		}
	/*
		public function get currentName():String{
			_name = "";
			if(_board.indexOf("mbot")>-1){
				_name = "mBot";
			}else if(_board.indexOf("arduino")>-1){
				_name = "Arduino "+_device.substr(0,1).toLocaleUpperCase()+_device.substr(1,_device.length);
			}
			return _name;
		}
	*/
		public function get currentBoard():String{
//			LogManager.sharedManager().log("currentBoard:"+_board);
			return _board;
		}
		public function get currentDevice():String{
			return _device;
		}
	}
}