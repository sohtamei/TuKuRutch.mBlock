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

// Specs.as
// John Maloney, April 2010
//
// This file defines the command blocks and categories.
// To add a new command:
//		a. add a specification for the new command to the commands array
//		b. add a primitive for the new command to the interpreter

package {
	import flash.display.Bitmap;
	import flash.filesystem.File;
	
	import assets.Resources;
	
	import cc.makeblock.util.FileUtil;
	

public class Specs {

	public static const GET_VAR:String = "readVariable";
	public static const SET_VAR:String = "setVar:to:";
	public static const CHANGE_VAR:String = "changeVar:by:";
	public static const GET_LIST:String = "contentsOfList:";
	public static const CALL:String = "call";
	public static const PROCEDURE_DEF:String = "procDef";
	public static const GET_PARAM:String = "getParam";

	public static const motionCategory:int = 1;
	public static const looksCategory:int = 2;
	public static const soundCategory:int = 3;
	public static const penCategory:int = 4;
	public static const eventsCategory:int = 5;
	public static const controlCategory:int = 6;
	public static const sensingCategory:int = 7;
	public static const operatorsCategory:int = 8;
	public static const dataCategory:int = 9;
	public static const myBlocksCategory:int = 10;
	public static const listCategory:int = 12;
	public static const extensionsCategory:int = 20;

	public static const variableColor:uint = 0xEE7D16; // Scratch 1.4: 0xF3761D
	public static const listColor:uint = 0xCC5B22; // Scratch 1.4: 0xD94D11
	public static const procedureColor:uint = 0x638DD9; // 0x531E99;
	public static const parameterColor:uint = 0x5947B1;
	public static const extensionsColor:uint = 0x0a8698;//0x75980a;//0x98980a//0x98510a;
//0x2980b9;//0x4B4A60; // 0x72228C; // 0x672D79;

	private static const undefinedColor:int = 0xD42828;

	private static const categories:Array = [];

	public static function blockColor(categoryID:int):int {
		if (categoryID > 100) categoryID -= 100;
		for each (var entry:Array in categories) {
			if (entry[0] == categoryID) return entry[2];
		}
		return undefinedColor;
	}

	public static function entryForCategory(categoryName:String):Array {
		for each (var entry:Array in categories) {
			if (entry[1] == categoryName) return entry;
		}
		return [1, categoryName, 0xFF0000]; // should not happen
	}

	public static function nameForCategory(categoryID:int):String {
		if (categoryID > 100) categoryID -= 100;
		for each (var entry:Array in categories) {
			if (entry[0] == categoryID) return entry[1];
		}
		return "Unknown";
	}

	public static function IconNamed(name:String):* {
		// Block icons are 2x resolution to look better when scaled.
		var icon:Bitmap;
		if (name == "greenFlag") icon = Resources.createBmp('flagIcon');
		if (name == "stop") icon = Resources.createBmp('stopIcon');
		if (name == "turnLeft") icon = Resources.createBmp('turnLeftIcon');
		if (name == "turnRight") icon = Resources.createBmp('turnRightIcon');
		if (icon != null) icon.scaleX = icon.scaleY = 0.5;
		return icon;
	}
	
	static private function Init():void
	{
		var content:String = FileUtil.ReadString(File.applicationDirectory.resolvePath("assets/blockSpec.xml"));
		var xml:XML = XML(content);
		var item:XML;
		for each(item in xml.category){
			categories.push([item.@id.toString(), item.@name.toString(), parseInt(item.@color.toString())]);
		}
		var emptyItem:Array = ["--"];
		for each(item in xml.command){
			var data:Array;
			if(item.hasOwnProperty("@category")){
				data = [item.@spec.toString(), item.@type.toString(), item.@category.toString(), item.@opcode.toString()];
				var argsStr:String = item.toString();
				if(argsStr){
					data.push.apply(null, JSON.parse(argsStr));
				}
			}else{
				data = emptyItem;
			}
			commands.push(data);
		}
	}
	
	Init();

	public static const commands:Array = [];
}}
