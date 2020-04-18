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
import flash.utils.setTimeout;

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
		if(extensionDict && extensionDict.name == name)
			return;

		var extObj:Object = null;
		for each(var e:Object in _extensionList){
			if(e.name==name){
				extObj = e;
				break;
			}
		}
		if(null == extObj)
			return;

		if(extensionDict) {
			SharedObjectManager.sharedManager().setObject(extensionDict.name+"_selected", false);
			ConnectionManager.sharedManager().onRemoved(extensionDict.name);
			extensionDict = null;
		}

		SharedObjectManager.sharedManager().setObject(name+"_selected", true);
		loadRawExtension(extObj);
	//	if(ConnectionManager.sharedManager().isConnected)
	//		setTimeout(ConnectionManager.sharedManager().onReOpen,1000);
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

	private var _dialog:DialogBox = new DialogBox();
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
						_dialog.addTitle(Translator.map('Error in json file'));
						_dialog.addButton(Translator.map('Close'), _dialog.cancel);
						_dialog.setText(e.toString());
						_dialog.showOnStage(Main.app.stage);
						Main.app.scriptsPart.appendMessage(e.toString());
					}
				}
			}
			_extensionList.sortOn("sort", Array.NUMERIC);
		}
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
			ext = new ScratchExtension(extObj.name, extObj.port);
		}
									ext.docPath = extObj.docPath;

									ext.boardType = extObj.boardType;
		if(extObj.sort)				ext.sort = extObj.sort;
		if(extObj.helpURL)			ext.helpURL = extObj.helpURL;
		if(extObj.productInfoURL)	ext.productInfoURL = extObj.productInfoURL;
		if(extObj.sampleDir)		ext.sampleDir = extObj.sampleDir;
									ext.javascriptURL = extObj.javascriptURL;		// LoadJS
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
									ext.blockSpecs = extObj.blockSpecs;
									ext.menus = extObj.menus;
		if(extObj.values)			ext.values = extObj.values;
		if(extObj.translators)		ext.translators = extObj.translators;

//									ext.showBlocks = true;
//		if(extObj.url)				ext.url = extObj.url;
//		if(extObj.extensionHost)	ext.host = extObj.extensionHost;
//		if(extObj.extensionType)	ext.type = extObj.extensionType;
//		if(extObj.firmware)			ext.firmware = extObj.firmware;
//		if(extObj.host)				ext.host = extObj.host; // non-local host allowed but not saved in project
//		if(extObj.sort)				ext.sort = extObj.sort;

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
		for (var i:int = 0; i < app.palette.numChildren; i++) {
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