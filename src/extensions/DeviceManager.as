package extensions
{
	public class DeviceManager
	{
		private static var _instance:DeviceManager;
		private var _device:String = "";
		private var _board:String = "";
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
			MBlock.app.extensionManager.singleSelectExtension("remoconRobo");
		}
		public function checkCurrentBoard(board:String):Boolean{
			return _board==board;
		}
		public function get currentBoard():String{
			return _board;
		}
		public function get currentDevice():String{
			return _device;
		}
	}
}