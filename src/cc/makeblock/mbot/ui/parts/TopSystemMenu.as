package cc.makeblock.mbot.ui.parts
{
	import flash.display.NativeMenu;
	import flash.display.NativeMenuItem;
	import flash.display.Stage;
	import flash.events.Event;
	import flash.filesystem.File;
	import flash.net.URLRequest;
	import flash.net.navigateToURL;
	
	import cc.makeblock.menu.MenuUtil;
	import cc.makeblock.menu.SystemMenu;
	
	import extensions.ArduinoManager;
	import extensions.ConnectionManager;
	import extensions.ExtensionManager;
	import extensions.ScratchExtension;
	
	import translation.Translator;
	
	import util.SharedObjectManager;

	import cc.makeblock.mbot.util.PopupUtil;

	public class TopSystemMenu extends SystemMenu
	{
		public function TopSystemMenu(stage:Stage, path:String)
		{
			super(stage, path);
			var menu:NativeMenu = getNativeMenu();

			menu.getItemByName("File").submenu.addEventListener(Event.DISPLAYING, clearTool);
			register("File", __onFile);

			menu.getItemByName("Connect").submenu.addEventListener(Event.DISPLAYING, __onShowConnect);
			register("Connect", __onConnect);

		//	menu.getItemByName("Edit").submenu.addEventListener(Event.DISPLAYING, __onShowEditMenu);
		//	register("Edit", __onEdit);

			menu.getItemByName("Robots").submenu.addEventListener(Event.DISPLAYING, __onShowExtMenu);
			register("Clear Cache", ArduinoManager.sharedManager().clearTempFiles);
			register("Convert robot.json to PC mode firmware", ArduinoManager.sharedManager().openArduinoIDE2);

			menu.getItemByName("Language").submenu.addEventListener(Event.DISPLAYING, __onShowLanguage);

			menu.getItemByName("Help").submenu.addEventListener(Event.DISPLAYING, clearTool);
			register("Help", __onHelp);

			register(" ShowStage ", __ShowStage);
			register(" Standard ", __Standard);
			menu.getItemByName(" Standard ").label = Translator.map("[Standard]");
			register(" Arduino ", __Arduino);
		}
		public function changeLang():void
		{
			MenuUtil.ForEach(getNativeMenu(), changeLangImpl);
		}
		
		private function changeLangImpl(item:NativeMenuItem):*
		{
			var index:int = getNativeMenu().getItemIndex(item);
			if(0 <= index && index < defaultMenuCount){
				return true;
			}
			if(item.name.indexOf("serial_") == 0){
				return;
			}
			var p:NativeMenuItem = MenuUtil.FindParentItem(item);
			if(p != null && p.name == "Robots"){
				if(p.submenu.getItemIndex(item) > 4){		// ?
					return true;
				}
			}
			for each(var name:String in [" ShowStage ", " Standard ", " Arduino "] ) {
				if(name == item.name) {
					switchStageMenu(_stageIndex);
					return;
				}
			}
			setItemLabel(item);
			if(item.name == "Language"){
				item = MenuUtil.FindItem(item.submenu, "set font size");
				setItemLabel(item);
				return true;
			}
		}
		
		private function setItemLabel(item:NativeMenuItem):void
		{
			var newLabel:String = Translator.map(item.name);
			if(item.label != newLabel){
				item.label = newLabel;
			}
		}
		
		private function clearTool(evt:Event):void
		{
			Main.app.clearTool();
		}

		private function __onFile(item:NativeMenuItem):void
		{
			switch(item.name) {
				case "New":				Main.app.createNewProject();			break;
				case "Load Project":	Main.app.runtime.selectProjectFile();	break;
				case "Save Project":	Main.app.saveFile();					break;
				case "Save Project As":	Main.app.exportProjectToFile();			break;
			}
		}
		
		private var initConnectMenuItemCount:int = -1;

		private function __onShowConnect(evt:Event):void
		{
			Main.app.clearTool();
			var menu:NativeMenu = evt.target as NativeMenu;
			
			if(initConnectMenuItemCount < 0){
				initConnectMenuItemCount = menu.numItems;
			}
			while(menu.numItems > initConnectMenuItemCount){
				menu.removeItemAt(menu.numItems-1);
			}

			var arr:Array = ConnectionManager.sharedManager().portlist;
			if(arr.length==0) {
				var nullItem:NativeMenuItem = new NativeMenuItem(Translator.map("no serial port"));
				nullItem.enabled = false;
				nullItem.name = "serial_"+"null";
				menu.addItem(nullItem);
			} else {
				for(var i:int=0;i<arr.length;i++){
					var item:NativeMenuItem = menu.addItem(new NativeMenuItem(Translator.map("Connect to Robot") + "(" + arr[i] + ")"));
					item.name = "serial_"+arr[i];
					
					item.enabled = true;
					item.checked = ConnectionManager.sharedManager().selectPort==arr[i] && ConnectionManager.sharedManager().isConnected;
				}
			}
			
			var connected:Boolean = ConnectionManager.sharedManager().isConnected;
			MenuUtil.FindItem(getNativeMenu(), "Set Robot to PC connection mode").enabled	= connected;
			MenuUtil.FindItem(getNativeMenu(), "Reset Default Program").enabled				= connected;
		}

		private function __onConnect(item:NativeMenuItem):void
		{
			var ext:ScratchExtension = Main.app.extensionManager.extensionByName();
			switch(item.name) {
				case "Set Robot to PC connection mode":
					ConnectionManager.sharedManager().upgrade(ext.pcmodeFW + ".cpp.standard.hex");
					break;
				case "Reset Default Program":
					ConnectionManager.sharedManager().upgrade(ext.normalFW + ".cpp.standard.hex");
					break;
				default:
					if(item.name.indexOf("serial_")>-1){
						var port:String = item.name.split("serial_").join("");
						ConnectionManager.sharedManager().onConnect(port);
					}
					break;
			}
		}
/*
		private function __onShowEditMenu(evt:Event):void
		{
			var menu:NativeMenu = evt.target as NativeMenu;
			MenuUtil.setEnable(menu.getItemByName("Undelete"),				Main.app.runtime.canUndelete());
			MenuUtil.setChecked(menu.getItemByName("Hide stage layout"),	Main.app.stageIsHided);
//			MenuUtil.setChecked(menu.getItemByName("Small stage layout"),	!Main.app.stageIsHided && Main.app.stageIsContracted);
//			MenuUtil.setChecked(menu.getItemByName("Turbo mode"),			Main.app.interp.turboMode);
			MenuUtil.setChecked(menu.getItemByName("Arduino mode"),			Main.app.stageIsArduino);
		}
*/
		private function __ShowStage(item:NativeMenuItem):void
		{
			switchStageMenu(0);
			Main.app.showStage(true);
		}
		private function __Standard(item:NativeMenuItem):void
		{
			switchStageMenu(1);
			Main.app.showStage(false);
		}
		private function __Arduino(item:NativeMenuItem):void
		{
			switchStageMenu(2);
			Main.app.showArduino();
		}

		private var _stageIndex:int = 1;
		private function switchStageMenu(index:int):void
		{
			Main.app.clearTool();
			_stageIndex = index;
			var menu:NativeMenu = getNativeMenu();
			var i:int;
			var offLabels:Array = [" ShowStage ", " Standard ", " Arduino "];
			var onLabels:Array  = ["[ShowStage]", "[Standard]", "[Arduino]"];

			for(i = 0; i < 3; i++) {
				var label:String = (i == index) ? onLabels[i]: offLabels[i];
				menu.getItemByName(offLabels[i]).label = Translator.map(label);
			}
		}
/*
		private function __onEdit(item:NativeMenuItem):void
		{
			switch(item.name){
				case "Undelete":			Main.app.runtime.undelete();	break;
				case "Hide stage layout":	Main.app.toggleHideStage();		break;
				case "Small stage layout":	Main.app.toggleSmallStage();	break;
				case "Turbo mode":			Main.app.toggleTurboMode();		break;
				case "Arduino mode":		Main.app.changeToArduinoMode();	break;
			}
		}
*/
		private var initExtMenuItemCount:int = -1;
		
		private function __onShowExtMenu(evt:Event):void
		{
			Main.app.clearTool();
			var item:NativeMenu = evt.target as NativeMenu;
			var list:Array = Main.app.extensionManager.extensionList;
			if(list.length==0){
				Main.app.extensionManager.copyLocalFiles();
				SharedObjectManager.sharedManager().setObject("first-launch",false);
			}
			if(initExtMenuItemCount < 0){
				initExtMenuItemCount = item.numItems;
			}
			while(item.numItems > initExtMenuItemCount){
				item.removeItemAt(item.numItems-1);
			}
			list = Main.app.extensionManager.extensionList;
			for(var i:int=0;i<list.length;i++){
				var extName:String = list[i].name;
				var subMenuItem:NativeMenuItem = item.addItem(new NativeMenuItem(Translator.map(extName)));
				subMenuItem.name = extName;
				subMenuItem.label = Translator.map(extName);
				subMenuItem.checked = Main.app.extensionManager.checkExtensionSelected(extName);
				register(extName, __onExtensions);
			}
		}
		
		private function __onExtensions(item:NativeMenuItem):void
		{
			Main.app.extensionManager.onSelectExtension(item.name);
		}
		
		private function __onShowLanguage(evt:Event):void
		{
			Main.app.clearTool();
			var languageMenu:NativeMenu = evt.target as NativeMenu;
			if(languageMenu.numItems <= 2){
				for each (var entry:Array in Translator.languages) {
					var item:NativeMenuItem = languageMenu.addItemAt(new NativeMenuItem(entry[1]), languageMenu.numItems-2);
					item.name = entry[0];
					item.checked = Translator.currentLang==entry[0];
				}
				languageMenu.addEventListener(Event.SELECT, __onLanguageSelect);
			}else{
				for each(item in languageMenu.items){
					if(item.isSeparator){
						break;
					}
					MenuUtil.setChecked(item, Translator.currentLang==item.name);
				}
			}
			try{
				var fontItem:NativeMenuItem = languageMenu.items[languageMenu.numItems-1];
				for each(item in fontItem.submenu.items){
					MenuUtil.setChecked(item, Translator.currentFontSize==int(item.label));
				}
			}catch(e:Error){
				
			}
		}
		
		private function __onLanguageSelect(evt:Event):void
		{
			var item:NativeMenuItem = evt.target as NativeMenuItem;
			if(item.name == "setFontSize"){
				Translator.setFontSize(int(item.label));
			}else{
				Translator.setLanguage(item.name);
			}
		}
		
		private function __onHelp(item:NativeMenuItem):void
		{
			switch(item.name) {
				case "Support Site":
					navigateToURL(new URLRequest(Main.app.extensionManager.extensionByName().helpURL),"_blank");
					break;
				case "Robot/Board Information":
					navigateToURL(new URLRequest(Main.app.extensionManager.extensionByName().productInfoURL),"_blank");
					break;
				case "About TuKuRutch":
					Main.app.openSwf("welcome.swf");
					break;
			}
		}
	}
}