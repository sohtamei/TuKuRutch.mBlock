package cc.makeblock.mbot.util
{
	import flash.display.NativeWindow;
	import flash.events.Event;
	import translation.Translator;

	public class AppTitleMgr
	{
		static public const Instance:AppTitleMgr = new AppTitleMgr();
		private var _window:NativeWindow;
		private var _title:String;
		private var _isModified:Boolean;
		private var _ProjectName:String = "";
		
		public function init(window:NativeWindow):void
		{
			_window = window;
			_title = window.title;
			Translator.regChangeEvt(__onLangChanged, false);
		}
		
		private function __onLangChanged(evt:Event):void
		{
			updateTitle();
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