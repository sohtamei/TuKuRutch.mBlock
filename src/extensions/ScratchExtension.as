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

// ScratchExtension.as
// John Maloney, March 2013
//
// Contains the name, port number, and block specs for an extension, as well as its runtime state.
// This file also defines the extensions built into Scratch (e.g. WeDo, PicoBoard).
//
// Extension block types:
//	' ' - command block
//  'w' - command block that waits
//	'r' - reporter block (returns a number or string)
//	'R' - http reporter block that waits for the callback (returns a number or string)
//	'b' - boolean reporter block
//	'-' - (not actually a block) add some blank space between blocks
//
// Possible argument slots:
//	'%n' - number argument slot
//	'%s' - string argument slot
//	'%b' - boolean argument slot

package extensions {
import flash.utils.Dictionary;

import cc.makeblock.util.StringChecker;

import util.SharedObjectManager;

public class ScratchExtension {

	public var name:String = '';
	public var port:int;

	public var docPath:String = "";
	public var boardType:String;
	public var sort:int = 10;
	public var helpURL:String = "";
	public var productInfoURL:String = "";
	public var sampleDir:String = "";
	private var _javascriptURL:String = ''; // URL to load a javascript extension
	public var normalFW:String = "";
	public var pcmodeFW:String = "";
	public var prefs:Array = [];

	public var header:String = "";
	public var setup:String = "";
	public var loop:String = "";
	public var blockSpecs:Array = [];
	public var blockSpecsSize:int = 0;
	public var menus:Object = {};
	public var values:Object = {};
	public var translators:Object = {};
	public var scratch3ext:String = "";
	public var scratch3burn:Array = [];
	public var scratch3constructor:String = "";
	public var scratch3blocks:String = "";
	public var scratch3menus:String = "";
	public var scratch3funcs:String = "";

	public var useSerial:Boolean = false;

	public var isInternal:Boolean;
	public var useScratchPrimitives:Boolean; // true for extensions built into Scratch (WeDo, PicoBoard) that have custom primitives
	private var _showBlocks:Boolean;
	public var thumbnailMD5:String = ''; // md5 has for extension image shown in extension library
	public var tags:Array = []; // tags for the extension library filter
	// Runtime state
	public var stateVars:Object = {};
	public var lastPollResponseTime:int;
	public var problem:String = '';
	public var success:String = 'Okay';
	private var _jsEngine:JavaScriptEngine;

//	public var firmware:String = "";
//	public var url:String = ''; // URL for extension documentation page (with helper app download link, if appropriate)
//	public var isBusy:Boolean = false;
//	public var nextID:int;
//	public var busy:Array = [];
//	public var waiting:Dictionary = new Dictionary(true);

	public function ScratchExtension(name:String, port:int) {
		this.name = name;
		this.port = port;
		_jsEngine = new JavaScriptEngine(name);
	}
	
	public function getStateVar(key:String):*
	{
		var value:* = stateVars[key];
		if(value == "true"){
			return true;
		}else if(value == "false"){
			return false;
		}else if(StringChecker.IsNumber(value)){
			return parseFloat(value);
		}
		return value || "";
	}
	
	public function set showBlocks(v:Boolean):void{
		_showBlocks = v;
		SharedObjectManager.sharedManager().setObject(name+"_show",v);
	}
	public function get showBlocks():Boolean{
		_showBlocks = SharedObjectManager.sharedManager().getObject(name+"_show",true) as Boolean;
		return _showBlocks;
	}
	public function getValue(label:*):*{
		if(typeof label=="number"){
			return label;
		}
		var n:* = this.values[label];
		if(n==null||n==undefined){
			return label;
		}
		return n;
	}
	public function get javascriptURL():String{
		return _javascriptURL;
	}
	public function set javascriptURL(v:String):void{
		if(v){
		//	_jsEngine.loadJS(this.docPath+v);
			_jsEngine.loadJS("app:/ext/libraries/Common/"+v);
		}
		_javascriptURL = v;
	}
	public function get js():JavaScriptEngine{
		return _jsEngine;
	}
}}
