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

import blocks.Block;

import cc.makeblock.interpreter.RemoteCallMgr;
import cc.makeblock.util.FileUtil;

import translation.Translator;

import uiwidgets.IndicatorLight;

import util.JSON;
import util.ReadStream;
import util.SharedObjectManager;

public class ExtensionManager {
	private var app:Main;
	private var extensionDict:Object = new Object(); // extension name -> extension record
	private var justStartedWait:Boolean;

	public function ExtensionManager(app:Main) {
		this.app = app;
		clearImportedExtensions();
	}

	public function extensionActive(extName:String):Boolean {
		return extensionDict.hasOwnProperty(extName);
	}

	public function isInternal(extName:String):Boolean {
		return (extensionDict.hasOwnProperty(extName) && extensionDict[extName].isInternal);
	}

	public function clearImportedExtensions():void {
		// Clear imported extensions before loading a new project.
		extensionDict = {};
	}

	// -----------------------------
	// Block Specifications
	//------------------------------

	public function specForCmd(op:String):Array {
		// Return a command spec array for the given operation or null.
		var count:int=0;
		for each (var ext:ScratchExtension in extensionDict) {
			var prefix:String = ext.useScratchPrimitives ? '' : (ext.name + '.');
			trace(count++);
			for each (var spec:Array in ext.blockSpecs) {
				if(spec.length <= 2){
					continue;
				}
				if(isCommonExt(ext.name)){
					if ((prefix + spec[2]) == op) {
						return [spec[1], spec[0], Specs.extensionsCategory, prefix + spec[2], spec.slice(3)];
					}
				}else{
					if(op.split(".")[1] == spec[2]){
						return [spec[1], spec[0], Specs.extensionsCategory, prefix + spec[2], spec.slice(3)];
					}
				}
			}
		}
		return null;
	}

	// -----------------------------
	// Enable/disable/reset
	//------------------------------

	public function setEnabled(extName:String, flag:Boolean):void {
		var ext:ScratchExtension = extensionDict[extName];
		if (ext && ext.showBlocks != flag) {
			ext.showBlocks = flag;
		}
	}

	public function isEnabled(extName:String):Boolean {
		var ext:ScratchExtension = extensionDict[extName];
		return ext ? ext.showBlocks : false;
	}

	public function enabledExtensions():Array {
		
		// Answer an array of enabled extensions, sorted alphabetically.
		var result:Array = [];
		var ext:ScratchExtension;
		for each (ext in extensionDict) {
			result.push(ext);
		}
		result.sortOn('sort');
		return result;
	}
	public function allExtensions():Array {
		// Answer an array of enabled extensions, sorted alphabetically.
		var result:Array = [];
		var ext:ScratchExtension;
		for each (ext in extensionDict) {
			result.push(ext);
		}
		result.sortOn('sort');
		return result;
	}
	public function extensionByName(extName:String):ScratchExtension{
		var ext:ScratchExtension = extensionDict[extName];
		return ext;
	}
	public function stopButtonPressed():* {
		// Send a reset_all command to all active extensions.
		var args:Array = [];
		for each (var ext:ScratchExtension in enabledExtensions()) {
			ext.js.call('resetAll', args, ext);
//			RemoteCallMgr.Instance.call(null, 'resetAll', args, ext);
		}
	}

	// -----------------------------
	// Importing
	//------------------------------
	public function openExtensionMenu(e):void{
		
	}
	private var _extensionList:Array = [];
	public function get extensionList():Array{
		return _extensionList;
	}
	public function onSelectExtension(name:String):void{
		if(name=="_import_"){
			return;
		}
		/*if(isMakeBlockExt(name)){
			return;
		}*/
		var ext:Object = findExtensionByName(name);
		if(null == ext){
			return;
		}
		var extensionSelected:Boolean = !checkExtensionSelected(name);
		SharedObjectManager.sharedManager().setObject(name+"_selected",extensionSelected);
		if(extensionSelected){
			loadRawExtension(ext);
			if(ConnectionManager.sharedManager().isConnected){
				setTimeout(ConnectionManager.sharedManager().onReOpen,1000);
			}
		}else{
			unloadRawExtension(ext);
		}
	}
	static public function isCommonExt(extName:String):Boolean
	{
		switch(extName){
			case "Arduino":
			case "Communication":
			case "Joystick(Arduino Mode Only)":
				return true;
		}
		return false;
	}
	static public function isMakeBlockExt(extName:String):Boolean
	{
		var ext:Object = Main.app.extensionManager.findExtensionByName(extName);
		return ext != null /*&& ext.isMakeBlockBoard*/;
	}
	public function singleSelectExtension(name:String):void{
		var ext:Object = findExtensionByName(name);
		if(null == ext){
			return;
		}
		for each(var tempExt:Object in _extensionList){
			var extName:String = tempExt.extensionName;
			if(!isMakeBlockExt(extName)){
				continue;
			}
			if(checkExtensionSelected(extName)){
				SharedObjectManager.sharedManager().setObject(extName+"_selected",false);
				ConnectionManager.sharedManager().onRemoved(extName);
				delete extensionDict[extName];
			}
		}
		SharedObjectManager.sharedManager().setObject(name+"_selected",true);
		loadRawExtension(ext);
	}
	public function findExtensionByName(name:String):Object{
		for each(var ext:Object in _extensionList){
			if(ext.extensionName==name){
				return ext;
			}
		}
		return null;
	}
	public function checkExtensionSelected(name:String):Boolean{
		return SharedObjectManager.sharedManager().getObject(name+"_selected",false);
	}
	public function checkExtensionEnabled():Boolean{
		var list:Array = extensionList;
		for(var i:uint=0;i<list.length;i++){
			var n:String = list[i].extensionName;
			if(checkExtensionSelected(n)){
				return true;
			}
		}
		return false;
	}

	public function copyLocalFiles():void{
		Main.app.track("copy local files...");
		copyDir("media/mediaLibrary.json");
	}
	public function importExtension():void {
		_extensionList = [];
		//重新加载所有的扩展时，应该清除extensionDict，解决扩展面板删除扩展时，实时更新选项卡
		extensionDict = {};
		var docs:Array = File.applicationDirectory.resolvePath("ext/libraries/").getDirectoryListing();
		for each(var doc:File in docs){
			if(!doc.isDirectory){
				continue;
			}
			var fs:Array = doc.getDirectoryListing();
			for each(var f:File in fs){
				if(f.extension=="s2e"||f.extension=="json"){
					var extObj:Object = util.JSON.parse(FileUtil.ReadString(f));
					extObj.srcPath = f.url;
					_extensionList.push(extObj);
					if(checkExtensionSelected(extObj.extensionName)){
						loadRawExtension(extObj);
					}
				}
			}
			_extensionList.sortOn("sort", Array.NUMERIC);
		}
		
		return;
	}

	static private function copyDir(dirName:String, destDirName:String=null):void
	{
		var fromFile:File = File.applicationDirectory.resolvePath(dirName);
		var toFile:File = File.applicationStorageDirectory.resolvePath("mBlock").resolvePath(destDirName || dirName);
		fromFile.copyTo(toFile, true);
	}
	
	public function extensionsToSave():Array {
		// Answer an array of extension descriptor objects for imported extensions to be saved with the project.
		var result:Array = [];
		for each (var ext:ScratchExtension in extensionDict) {
			if(!ext.showBlocks) continue;

			var descriptor:Object = {};
			descriptor.extensionName = ext.name;
			descriptor.blockSpecs = ext.blockSpecs;
			descriptor.menus = ext.menus;
			if(ext.port) descriptor.extensionPort = ext.port;
			else if(ext.javascriptURL) descriptor.javascriptURL = ext.javascriptURL;
			result.push(descriptor);
		}
		return result;
	}

	public function callCompleted(extensionName:String, id:Number):void {
		var ext:ScratchExtension = extensionDict[extensionName];
		if (ext == null) return; // unknown extension

		var index:int = ext.busy.indexOf(id);
		if(index > -1) ext.busy.splice(index, 1);
	}

	public function reporterCompleted(extensionName:String, id:Number, retval:*):void {
		var ext:ScratchExtension = extensionDict[extensionName];
		if (ext == null) return; // unknown extension
		for(var b:Object in ext.waiting) {
			var block:Block = b as Block;
			if(ext.waiting[b] === id) {
				delete ext.waiting[b];
				if(retval != null){
					block.response = retval;
					block.requestState = 2;
				}
			}
		}
	}

	public function loadRawExtension(extObj:Object):void {
	
		var ext:ScratchExtension = extensionDict[extObj.extensionName];
		if(ext){
			return;
		}
		if(!ext || (ext.blockSpecs && ext.blockSpecs.length)){
			ext = new ScratchExtension(extObj.extensionName, extObj.extensionPort);
		}
		ext.blockSpecs = extObj.blockSpecs;
		if(extObj.url) ext.url = extObj.url;
		if(extObj.extensionHost) ext.host = extObj.extensionHost;
		if(extObj.extensionType) ext.type = extObj.extensionType;
		var srcArr:Array = extObj.srcPath.split("/");
		ext.docPath = extObj.srcPath.split(srcArr[srcArr.length-1]).join("");
		ext.srcPath = ext.docPath+"/src";
		//ext.showBlocks = true;
		ext.menus = extObj.menus;
		if(extObj.values){
			ext.values = extObj.values;
		}
		if(extObj.translators){
			ext.translators = extObj.translators;
		}
		if(extObj.firmware){
			ext.firmware = extObj.firmware;
		}
		ext.javascriptURL = extObj.javascriptURL;	
		if (extObj.host) ext.host = extObj.host; // non-local host allowed but not saved in project
		if(ext.port==0&&ext.javascriptURL!=""){
			ext.useSerial = true;
		}else{
			ext.useSerial = false;
		}
		if(extObj.sort){
			ext.sort = extObj.sort;
		}
		extensionDict[extObj.extensionName] = ext;
		parseTranslators(ext);
//		parseAllTranslators();
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
	private function unloadRawExtension(extObj:Object):void{
		ConnectionManager.sharedManager().onRemoved(extObj.extensionName);
		delete extensionDict[extObj.extensionName];
//		parseAllTranslators();
		Main.app.translationChanged();
		Main.app.updatePalette();
		// Update the indicator
		for (var i:int = 0; i < app.palette.numChildren; i++) {
			var indicator:IndicatorLight = app.palette.getChildAt(i) as IndicatorLight;
			if (indicator && indicator.target === extObj) {
				updateIndicator(indicator, indicator.target, true);
				break;
			}
		}
	}
	public function parseAllTranslators():void{
		for each (var ext:ScratchExtension in extensionDict) {
			parseTranslators(ext);
		}
	}
	private function parseTranslators(ext:ScratchExtension):void{
		if(null == ext.translators){
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
	public function loadSavedExtensions(savedExtensions:Array):void {
		// Reset the system extensions and load the given array of saved extensions.
		for each (var extObj:Object in savedExtensions) {
			if (!('extensionName' in extObj)) {
				continue;
			}
			if(!checkExtensionSelected(extObj.extensionName)){
				onSelectExtension(extObj.extensionName);
			}
		}
	}

	// -----------------------------
	// Menu Support
	//------------------------------

	public function menuItemsFor(op:String, menuName:String):Array {
		// Return a list of menu items for the given menu of the extension associated with op or null.
		var i:int = op.lastIndexOf('.');
		if (i < 0) return null;
		var ext:ScratchExtension = extensionDict[op.slice(0, i)];
		if (ext == null) return null; // unknown extension
		return ext.menus[menuName];
	}

	// -----------------------------
	// Status Indicator
	//------------------------------

	public function updateIndicator(indicator:IndicatorLight, ext:ScratchExtension, firstTime:Boolean = false):void {
		
		var msecsSinceLastResponse:uint = getTimer() - ext.lastPollResponseTime;
		if(ext.useSerial){
			if (!ConnectionManager.sharedManager().isConnected) {
				indicator.setColorAndMsg(0xE00000, Translator.map('Disconnected'));
			}
			else if (ext.problem != '') indicator.setColorAndMsg(0xE0E000, ext.problem);
			else indicator.setColorAndMsg(0x00C000, ext.success);
		}else{
			if (msecsSinceLastResponse > 500) indicator.setColorAndMsg(0xE00000, Translator.map('Disconnected'));
			else if (ext.problem != '') indicator.setColorAndMsg(0xE0E000, ext.problem);
			else indicator.setColorAndMsg(0x00C000, ext.success);
		}
		
	}

	// -----------------------------
	// Execution
	//------------------------------

	public function call(extensionName:String, op:String, args:Array):void {
		var ext:ScratchExtension = extensionDict[extensionName];

		if (ext == null) return; // unknown extension
		httpCall(ext, op, args);
	}
	private function httpCall(ext:ScratchExtension, op:String, args:Array):void {
		ext.js.call(op,args,ext);
	}

	public function request(extensionName:String, op:String, args:Array, b:Block):void {
		var ext:ScratchExtension = extensionDict[extensionName];
		if (ext == null||(ext.useSerial&&!ConnectionManager.sharedManager().isConnected)||app.runtime.isRequest){
			// unknown extension, skip the block
			return;
		}
		if(b in ext.waiting){
		}else{
			ext.waiting[b] = ++ext.nextID;
			if(ext.nextID>50){
				ext.nextID = 0;
			}
		}
	}

	
	public function getStateVar(extensionName:String, varName:String, defaultValue:*):* {
		var ext:ScratchExtension = extensionDict[extensionName];
		if (ext == null) return defaultValue; // unknown extension
		var value:* = ext.stateVars[varName];
		return (value == undefined) ? defaultValue : value;
	}

	// -----------------------------
	// Polling
	//------------------------------

	public function step():void {
		// Poll all extensions.
		for each (var ext:ScratchExtension in extensionDict) {
			if (ext.showBlocks) {
				if((!ext.isInternal && ext.port > 0 && ext.useSerial == false)){
				//	httpPoll(ext);
				}
			}
		}
	}

	private function processPollResponse(ext:ScratchExtension, response:String):void {
		if (response == null) return;
		ext.lastPollResponseTime = getTimer();
		ext.problem = '';

		// clear the busy list unless we just started a command that waits
		if (justStartedWait) justStartedWait = false;
		else ext.busy = [];

		var lines:Array = response.split('\n');
		for each (var line:String in lines) {
			var tokens:Array = ReadStream.tokenize(line);
			if (tokens.length > 1) {
				var key:String = tokens[0];
				if (key.indexOf('_') == 0) { // internal status update or response
					if ('_busy' == key) {
						for (var i:int = 1; i < tokens.length; i++) {
							var id:int = parseInt(tokens[i]);
							if (ext.busy.indexOf(id) == -1) ext.busy.push(id);
						}
					}
					if ('_problem' == key) ext.problem = line.slice(9);
					if ('_success' == key) ext.success = line.slice(9);
				} else { // sensor value
					var val:String = tokens[1];
					var n:Number = Number(val);
					ext.stateVars[key] = isNaN(n) ? val : n;
				}
			}
		}
	}
}
}