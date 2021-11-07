/*
 * Scratch Project Editor and Player
 * Copyright (C) 2014 Massachusetts Institute of Technology
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License
 * as published by the Free Software Foundation; either version 2
 * of the License, or (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.
 */

// ExtensionManager.as
// John Maloney, September 2011
//
// Scratch extension manager. Maintains a dictionary of all extensions in use and manages
// socket-based communications with local and server-based extension helper applications.

package extensions {
import flash.filesystem.File;
import flash.utils.getTimer;

import cc.makeblock.util.FileUtil;

import translation.Translator;

import uiwidgets.IndicatorLight;
import uiwidgets.DialogBox;

import util.JSON;
import util.SharedObjectManager;

public class ExtensionManager {
	private var app:Main;
	private var extensionDict:ScratchExtension;		// current extension
	private var _extensionList:Array = [];

	public function ExtensionManager(app:Main) {
		this.app = app;
		extensionDict = null;
	}

	public function isInternal(extName:String):Boolean {
		return (!extensionDict && extensionDict.isInternal);
	}
/*
	public function clearImportedExtensions():void {
		// Clear imported extensions before loading a new project.
		extensionDict = null;
	}
*/
	// -----------------------------
	// Block Specifications
	//------------------------------

	// spec[1]:"play tone ..", spec[0]:"w", extensionsCategory:20, prefix+spec[2]:"remoconRobo.runBuzzerJ2", spec.slice(3):(初期値+obj)
	public function specForCmd(op:String):Array {
		// Return a command spec array for the given operation or null.
		var prefix:String = extensionDict.useScratchPrimitives ? '' : 'robot.';
		for each (var spec:Array in extensionDict.blockSpecs) {
			if(spec.length < 3)
				continue;

			if ((prefix + spec[2]) == op) {
				return [spec[1], spec[0], Specs.extensionsCategory, prefix + spec[2], spec.slice(3)];
			}
		}
		return null;
	}

	// -----------------------------
	// Enable/disable/reset
	//------------------------------

	public function setEnabled(extName:String, flag:Boolean):void {
		if (extensionDict && extensionDict.showBlocks != flag) {
			extensionDict.showBlocks = flag;
		}
	}

	public function isEnabled(extName:String):Boolean {
		return extensionDict ? extensionDict.showBlocks : false;
	}

	public function allExtensions():Array {
		// Answer an array of enabled extensions, sorted alphabetically.
		var result:Array = [];
		if(extensionDict)
			result.push(extensionDict);
		return result;
	}
	public function extensionByName(extName:String=null):ScratchExtension
	{
		if(extName == null || extName == extensionDict.name)
			return extensionDict;
		else
			return null;
	}
	public function stopButtonPressed():*
	{
		// Send a reset_all command to all active extensions.
		var args:Array = [];
//		extensionDict.js.call('resetAll', args, extensionDict);
//		RemoteCallMgr.Instance.call(null, 'resetAll', args, extensionDict);
	}

	// -----------------------------
	// Importing
	//------------------------------
	public function get extensionList():Array{
		return _extensionList;
	}
	public function singleSelectExtension():void
	{
		if(!extensionDict)
			onSelectExtension(_extensionList[0].name);
	}
	public function onSelectExtension(name:String):void
	{
		if(extensionDict && extensionDict.name == name) {
			// reload .json
			importExtension();
			return;
		}

		var extObj:Object = null;
		for each(var e:Object in _extensionList){
			if(e.name==name){
				extObj = e;
				break;
			}
		}
		if(null == extObj)
			return;

		// remove previous ext
		if(extensionDict) {
			SharedObjectManager.sharedManager().setObject(extensionDict.name+"_selected", false);
			ConnectionManager.sharedManager().onRemoved(extensionDict.name);
			extensionDict = null;
		}

		SharedObjectManager.sharedManager().setObject(name+"_selected", true);
		loadRawExtension(extObj);

		var arduinoIDE:String;
		var msg:String;
		switch(extensionDict.boardType.split(':')[1]) {
		case "esp32":
			arduinoIDE = "Arduino.1.18.11.esp";
			msg = "ESP32";
			break;
		case "samd":
			arduinoIDE = "Arduino.1.18.11.samd";
			msg = "koov";
			break;
		}
		if(arduinoIDE && !File.applicationDirectory.resolvePath("Arduino/"+arduinoIDE).exists) {
			var dialog:DialogBox = new DialogBox();
 			dialog.addTitle(Translator.map('TuKuRutch package Error'));
			dialog.setText(Translator.map('This TuKuRutch package does not support this robot. Please install TuKuRutch for ')+msg);
			dialog.addButton(Translator.map('Close'), null);
			dialog.showOnStage(Main.app.stage);
		}
	}
	public function checkExtensionSelected(name:String):Boolean{
		return SharedObjectManager.sharedManager().getObject(name+"_selected",false);
	}

	public function copyLocalFiles():void
	{
		Main.app.track("copy local files...");
		var dirName:String = "media/mediaLibrary.json";
		var fromFile:File = File.applicationDirectory.resolvePath(dirName);
		var toFile:File   = File.applicationStorageDirectory.resolvePath("mBlock").resolvePath(dirName);
		fromFile.copyTo(toFile, true);
	}

	public function importExtension():void
	{
		_extensionList = [];
		extensionDict = null;
		//重新加载所有的扩展时，应该清除extensionDict，解决扩展面板删除扩展时，实时更新选项卡
		var docs:Array = File.applicationDirectory.resolvePath("ext/libraries/").getDirectoryListing();
		for each(var doc:File in docs){
			if(!doc.isDirectory){
				continue;
			}
			var fs:Array = doc.getDirectoryListing();
			for each(var f:File in fs){
				if(f.extension=="s2e"||f.extension=="json"){
					try{
						var extObj:Object = util.JSON.parse(FileUtil.ReadString(f));
						extObj.docPath = f.url;
						var srcArr:Array = extObj.docPath.split("/");
						extObj.docPath = extObj.docPath.split(srcArr[srcArr.length-1]).join("");

						_extensionList.push(extObj);
						if(checkExtensionSelected(extObj.name)){
							loadRawExtension(extObj);
						}
					}catch(e:*){
						var _dialog:DialogBox = new DialogBox();
						_dialog.addTitle(Translator.map('Error in json file'));
						_dialog.setText(e.toString());
						_dialog.addButton(Translator.map('Close'), null);
						_dialog.showOnStage(Main.app.stage);
						Main.app.scriptsPart.appendMessage(e.toString());
					}
				}
			}
		}
		_extensionList.sortOn(["sort","name"], [Array.NUMERIC,Array.CASEINSENSITIVE]);
		return;
	}
/*
	public function extensionsToSave():Array {
		// Answer an array of extension descriptor objects for imported extensions to be saved with the project.
		var result:Array = [];
		var ext:ScratchExtension = extensionDict;
		if(ext.showBlocks) {
			var descriptor:Object = {};
			descriptor.name			= ext.name;
			descriptor.blockSpecs	= ext.blockSpecs;
			descriptor.menus		= ext.menus;
			if(ext.port) 				descriptor.extensionPort = ext.port;
			else if(ext.javascriptURL)	descriptor.javascriptURL = ext.javascriptURL;
			result.push(descriptor);
		}
		return result;
	}
*/
	public function loadRawExtension(extObj:Object):void
	{
		var ext:ScratchExtension = extensionDict;
		if(ext){
			return;
		}
		if(!ext || (ext.blockSpecs && ext.blockSpecs.length)){
			ext = new ScratchExtension(extObj.name, 0/*extObj.port*/);
		}
		ext.boardType		= "arduino:avr:uno";
		ext.javascriptURL	= "robot.js";
		ext.pcmodeFW		= extObj.docPath + "src/src";
		ext.setup			= "Serial.begin(115200);";
		ext.blockSpecs		= [];
		ext.menus			= {};
		ext.values			= {};
		ext.translators		= {ja:{}};
		ext.scratch3ext		= extObj.name;

									ext.docPath = extObj.docPath;

		if(extObj.boardType)		ext.boardType = extObj.boardType;
		if(extObj.sort)				ext.sort = extObj.sort;
		if(extObj.helpURL)			ext.helpURL = extObj.helpURL;
		if(extObj.productInfoURL)	ext.productInfoURL = extObj.productInfoURL;
		if(extObj.sampleDir)		ext.sampleDir = extObj.sampleDir;
		if(extObj.javascriptURL)	ext.javascriptURL = extObj.javascriptURL;		// LoadJS
		if(extObj.normalFW)			ext.normalFW = extObj.docPath + extObj.normalFW;
		if(extObj.pcmodeFW)			ext.pcmodeFW = extObj.docPath + extObj.pcmodeFW;
		if(extObj.libraryPath) {
			var toFile:File = new File(File.applicationDirectory.resolvePath("Arduino/portable/sketchbook/libraries/" + extObj.libraryPath).nativePath);
			File.applicationDirectory.resolvePath(extObj.docPath + extObj.libraryPath).copyTo(toFile, true);
		}
		if(extObj.prefs)			ext.prefs = extObj.prefs;

		if(extObj.header)			ext.header = extObj.header;
		if(extObj.setup)			ext.setup = extObj.setup;
		if(extObj.loop)				ext.loop = extObj.loop;
		if(extObj.blockSpecs)		ext.blockSpecs = extObj.blockSpecs.concat();
									ext.blockSpecsSize = ext.blockSpecs.length;
		if(extObj.menus)			ext.menus = extObj.menus;
		if(extObj.values)			ext.values = extObj.values;
		if(extObj.translators)		ext.translators = extObj.translators;
		if(extObj.scratch3ext)		ext.scratch3ext = extObj.scratch3ext;
		if(extObj.scratch3burn)		ext.scratch3burn = extObj.scratch3burn;

		var i:int;
		if(ext.boardType == "esp32:esp32:esp32") {
			var ArgTypesTbl3:Array = [
				["R", "status WIFI",		"statusWifi",				{remote:[		"s"],func:"statusWifi()"}],			// 0xFB
				["R", "scan WIFI",			"scanWifi",					{remote:[		"s"],func:"scanWifi()"}],			// 0xFC
				["R", "connect WIFI %s %s",	"connectWifi","ssid","pass",{remote:["s","s","B"],func:"connectWifi({0},{1})"}],// 0xFD
			];
			const CMD3_MIN:int = 0xFB;

			for(i = ext.blockSpecs.length; i < CMD3_MIN; i++)
				ext.blockSpecs.push([""]);
			ext.blockSpecs = ext.blockSpecs.concat(ArgTypesTbl3);
		}

		if(ext.port==0 && ext.javascriptURL!=""){
			ext.useSerial = true;
		}else{
			ext.useSerial = false;
		}
		extensionDict = ext;
		parseTranslators(ext);

		Main.app.translationChanged();
		Main.app.updatePalette();
		// Update the indicator
		for (i = 0; i < app.palette.numChildren; i++) {
			var indicator:IndicatorLight = app.palette.getChildAt(i) as IndicatorLight;
			if (indicator && indicator.target === ext) {
				updateIndicator(indicator, indicator.target, true);
				break;
			}
		}
	}
	public function parseAllTranslators():void{
		parseTranslators(extensionDict);
	}
	private function parseTranslators(ext:ScratchExtension):void{
		if(!ext || null == ext.translators){
			return;
		}
		for(var key:String in ext.translators){
			if(Translator.currentLang != key){
				continue;
			}
			var dict:Object = ext.translators[key];
			for(var entryKey:String in dict){
				Translator.addEntry(entryKey,dict[entryKey]);
			}
			break;
		}
	}

	// -----------------------------
	// Menu Support
	//------------------------------

	public function menuItemsFor(op:String, menuName:String):Array {
		// Return a list of menu items for the given menu of the extension associated with op or null.
		var i:int = op.lastIndexOf('.');
		if (i < 0) return null;
	//	if(op.slice(0, i) != extensionDict.name) return null;	// unknown extension
		return extensionDict.menus[menuName];
	}

	// -----------------------------
	// Status Indicator
	//------------------------------

	public function updateIndicator(indicator:IndicatorLight, ext:ScratchExtension, firstTime:Boolean = false):void {
		
		var msecsSinceLastResponse:uint = getTimer() - ext.lastPollResponseTime;
		if(ext.useSerial){
			if (!ConnectionManager.sharedManager().isConnected)
												indicator.setColorAndMsg(0xE00000, Translator.map('Disconnected'));
			else if (ext.problem != '')			indicator.setColorAndMsg(0xE0E000, ext.problem);
			else								indicator.setColorAndMsg(0x00C000, ext.success);
		}else{
			if (msecsSinceLastResponse > 500)	indicator.setColorAndMsg(0xE00000, Translator.map('Disconnected'));
			else if (ext.problem != '')			indicator.setColorAndMsg(0xE0E000, ext.problem);
			else								indicator.setColorAndMsg(0x00C000, ext.success);
		}
	}

	// -----------------------------
	// Execution
	//------------------------------

	public function getStateVar(extensionName:String, varName:String, defaultValue:*):* {
		if(extensionName != extensionDict.name)
			return defaultValue; // unknown extension
		var value:* = extensionDict.stateVars[varName];
		return (value == undefined) ? defaultValue : value;
	}

	// -----------------------------
	// Polling
	//------------------------------

	public function step():void {
		// Poll all extensions.
		if (extensionDict && extensionDict.showBlocks) {
			if((!extensionDict.isInternal && extensionDict.port > 0 && extensionDict.useSerial == false)){
			//	httpPoll(extensionDict);
			}
		}
	}
}
}