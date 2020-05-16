package cc.makeblock.mbot.ui.parts
{
	import flash.display.NativeMenu;
	import flash.display.NativeMenuItem;
	import flash.display.Stage;
	import flash.events.Event;
	import flash.filesystem.File;
	import flash.net.URLRequest;
	import flash.net.navigateToURL;
	import flash.net.InterfaceAddress;
	
	import cc.makeblock.menu.MenuUtil;
	import cc.makeblock.menu.SystemMenu;
	import cc.makeblock.util.getLocalAddress;

	import flash.geom.Point;
	import ui.parts.UIPart;
	import blockly.runtime.Interpreter;
	import blockly.runtime.Thread;
	import uiwidgets.DialogBox;
	import uiwidgets.IconButton;
	import uiwidgets.Menu;
	import cc.makeblock.interpreter.ArduinoFunctionProvider;
	
	import extensions.ArduinoManager;
	import extensions.ConnectionManager;
	import extensions.ExtensionManager;
	import extensions.ScratchExtension;
	
	import translation.Translator;
	
	import util.SharedObjectManager;
	import util.LogManager;

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
			register("Build PC mode firmware", ArduinoManager.sharedManager().buildPcmode);
			register("Open PC mode firmware", ArduinoManager.sharedManager().openPcmode);
			register("Build Normal firmware", ArduinoManager.sharedManager().buildNormal);
			register("Open Normal firmware", ArduinoManager.sharedManager().openNormal);

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

			var i:int;
			var item:NativeMenuItem;
			var arrP:Array = ConnectionManager.sharedManager().portlist;
			for(i=0;i<arrP.length;i++){
				item = menu.addItem(new NativeMenuItem(Translator.map("Connect to Robot") + "(" + arrP[i] + ")"));
				item.name = "serial_"+arrP[i];
				item.enabled = true;
				item.checked = ConnectionManager.sharedManager().connected(arrP[i]);
			}
			
			var arrS:Array = ConnectionManager.sharedManager().socketList;
			for(i=0;i<arrS.length;i++){
				item = menu.addItem(new NativeMenuItem(Translator.map("Connect to Robot") + "(" + arrS[i].address + ":" + arrS[i].name + ")"));
				item.name = "net_"+arrS[i].address;
				item.enabled = true;
				item.checked = ConnectionManager.sharedManager().connected(arrS[i].address);
			}

			if(arrP.length==0 && arrS.length==0) {
				item = menu.addItem(new NativeMenuItem(Translator.map("no serial port")));
				item.enabled = false;
				item.name = "serial_null";
			}

			var connected:Boolean = ConnectionManager.sharedManager().isConnectedUart;
			MenuUtil.FindItem(getNativeMenu(), "Setup WiFi").enabled						= connected;
			MenuUtil.FindItem(getNativeMenu(), "Set Robot to PC connection mode").enabled	= connected;
			MenuUtil.FindItem(getNativeMenu(), "Reset Default Program").enabled				= connected;
		}

		private function __onConnect(item:NativeMenuItem):void
		{
			var ext:ScratchExtension = Main.app.extensionManager.extensionByName();
			switch(item.name) {
				case "Set Robot to PC connection mode":
					ConnectionManager.sharedManager().burnFW(ext.pcmodeFW);
					break;
				case "Reset Default Program":
					ConnectionManager.sharedManager().burnFW(ext.normalFW);
					break;
				case "Setup WiFi":
					__setupWifi();
					break;
				case "(for network-port issue)":
					custom();
					break;
				default:
					if(item.name.indexOf("net_")>-1){
						ConnectionManager.sharedManager().toggle(item.name.split("net_")[1]);
					} else
					if(item.name.indexOf("serial_")>-1){
						ConnectionManager.sharedManager().toggle(item.name.split("serial_")[1]);
					}
					break;
			}
		}

		private var _currentIp:String = "";
		public function custom():void
		{
			if(_currentIp == "") {
				var local:InterfaceAddress = getLocalAddress();
				if(local) _currentIp = local.broadcast.substr(0,local.broadcast.length-3);
			}

			var dialog:DialogBox = new DialogBox;
			dialog.addTitle(Translator.map("(for network-port issue)"));
			dialog.addField("IP Address",100,_currentIp,true);
			dialog.addButton(Translator.map("Cancel"),null);
			dialog.addButton(Translator.map("Connect"),connectNow);
			dialog.showOnStage(Main.app.stage);

			function connectNow():void{
				var address:String = dialog.fields["IP Address"].text;
				ConnectionManager.sharedManager().addSockets(address, "custom");
				ConnectionManager.sharedManager().toggle(address);
			}
		}

		public function __setupWifi():void
		{
		//	var WlanStatus:Array = ["IDLE_STATUS","NO_SSID_AVAIL","SCAN_COMPLETED","CONNECTED","CONNECT_FAILED","CONNECTION_LOST","DISCONNECTED",];
			var realInterpreter:Interpreter = new Interpreter(new ArduinoFunctionProvider());

			var dialog:DialogBox = new DialogBox;
			dialog.addTitle(Translator.map('Setup WiFi'));
			dialog.addField('SSID',      150,'',true);
			dialog.addField('password',  150,'',true);
			dialog.addField('status',    150,'',true);
			dialog.addField('IP Address',150,'',true);
			dialog.addButton(Translator.map('Cancel'),null);
			dialog.addButton(Translator.map('Connect'),connectNow);
			dialog.addWidget(UIPart.makeMenuButton(Translator.map('Scan'), ssidMenu, true, CSS.textColor));
			dialog.showOnStage(Main.app.stage);

			var block:Object = {argList:[], method:"robot.statusWifi", retCount:1, type:"function"};
			var thread:Thread = realInterpreter.execute([block]);
			thread.finishSignal.add(_statusWifi, true);

			function _statusWifi(isInterput:Boolean):void{
				if(typeof(thread.resultValue) != 'string') return;
				Main.app.track(thread.resultValue);

				var paras:Array = thread.resultValue.split('\t');		// status, SSID, IP
				if(paras.length < 2) return;
				paras[0] = Number(paras[0]);

				dialog.fields["SSID"].text = paras[1];
				if(paras[0] == 3) {
					dialog.fields['status'].text = Translator.map('Connected');
					dialog.fields["IP Address"].text = paras[2];
					_currentIp = paras[2];
				} else {
					dialog.fields['status'].text = Translator.map('Disconnected')+'('+paras[0]+')';
				}
			}

			function ssidMenu(b:IconButton):void {
				if(!thread.isFinish) return;

				block = {argList:[], method:"robot.scanWifi", retCount:1, type:"function"};
				thread = realInterpreter.execute([block]);
				thread.finishSignal.add(_scanWifi, true);

				var m:Menu = new Menu();
				m.addItem(Translator.map('Scanning..'));
				var p:Point = b.localToGlobal(new Point(0, 0));
				m.showOnStage(Main.app.stage, p.x + 1, p.y + b.height - 1);

				function _scanWifi(isInterput:Boolean):void{
					if(typeof(thread.resultValue) != 'string') return;
					Main.app.track(thread.resultValue);

					var paras:Array = thread.resultValue.split('\t');		// status, SSID, IP
					m = new Menu(_menu);
					for(var i:int=0;i<paras.length;i++)
						m.addItem(paras[i], paras[i]);
					p = b.localToGlobal(new Point(0, 0));
					m.showOnStage(Main.app.stage, p.x + 1, p.y + b.height - 1);
				}

				function _menu(b:String):void {
					dialog.fields['SSID'].text = b;
				}
			}

			function connectNow():void{
				if(!thread.isFinish) return;

				var _ssid:String = dialog.fields['SSID'].text;
				var _pass:String = dialog.fields['password'].text;

				block = {argList:[{type:"string",value:_ssid}, {type:"string",value:_pass}],
						method:"robot.connectWifi", retCount:1, type:"function"};
				thread = realInterpreter.execute([block]);
				thread.finishSignal.add(_connectWifi, true);

				var dialog2:DialogBox = new DialogBox;
				dialog2.addTitle(Translator.map('Setup WiFi'));
				dialog2.setText(Translator.map('Connecting..'));
				dialog2.addButton(Translator.map('Close'),null);
				dialog2.showOnStage(Main.app.stage);

				function _connectWifi(isInterput:Boolean):void{
					var result:int;
					if(typeof(thread.resultValue) == 'number') result = thread.resultValue;
					if(result == 3)
						dialog2.setText(Translator.map('Connected !'));
					else
						dialog2.setText(Translator.map('Failed !')+' ('+result+')');
				}
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
				case "Enable Log":
					item.checked = !item.checked;
					LogManager.sharedManager().enableDebug(item.checked);
					break;
			}
		}
	}
}