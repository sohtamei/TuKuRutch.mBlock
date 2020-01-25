package cc.makeblock.mbot.util
{
	import flash.display.NativeWindow;

	public class AppTitleMgr
	{
		static public const Instance:AppTitleMgr = new AppTitleMgr();
		private var _window:NativeWindow;
		private var _title:String;
		private var _ProjectName:String = "";
		private var _isModified:Boolean;
		
		public function init(window:NativeWindow):void
		{
			_window = window;
			_title = window.title;
		}
		
		public function setProjectName(name:String):void
		{
			_ProjectName = name;
			updateTitle();
		}
		
		public function setProjectModifyInfo(isModified:Boolean):void
		{
			_isModified = isModified;
			updateTitle();
		}
		
		private function updateTitle():void
		{
			if(_window.closed) return;
			_window.title = _title + " - " + _ProjectName + (_isModified ? " *": "");
		}
	}
}