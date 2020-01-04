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

// TopBarPart.as
// John Maloney, November 2011
//
// This part holds the Scratch Logo, cursor tools, screen mode buttons, and more.

package ui.parts {
	import flash.display.Bitmap;
	import flash.display.Graphics;
	import flash.display.Sprite;
	import flash.events.MouseEvent;
	import flash.text.TextField;
	import flash.text.TextFieldAutoSize;
	import flash.text.TextFormat;
	
	import assets.Resources;
	
	import cc.makeblock.mbot.util.AppTitleMgr;
	
	import extensions.ConnectionManager;
	
	import translation.Translator;
	
	import uiwidgets.CursorTool;
	import uiwidgets.IconButton;
	import uiwidgets.SimpleTooltips;

	public class TopBarPart extends UIPart {
		private var copyTool:IconButton;
		private var cutTool:IconButton;
		private var growTool:IconButton;
		private var shrinkTool:IconButton;
		private var connectTool:IconButton;
		private var toolOnMouseDown:String;
	
		private var mcNotice:Sprite = new Sprite;
		public var offlineNotice:TextField = new TextField;
	
		public function TopBarPart(app:MBlock) {
			this.app = app;
			addButtons();
			refresh();
		}
	
		protected function addButtons():void {
			addTextButtons();
			addToolButtons();
		}
	
		public static function strings():Array {
			return ['File', 'Edit', 'Tips', 'Duplicate', 'Delete', 'Grow', 'Shrink', 'Block help', 'Offline Editor'];
		}
	
		protected function removeTextButtons():void {
			if (mcNotice.parent) {
				removeChild(mcNotice);
				mcNotice.removeEventListener(MouseEvent.CLICK,onClickLink); 
			}
		}
	
		public function updateTranslation():void {
			removeTextButtons();
			addTextButtons();
			refresh();
		}
		public function setWidthHeight(w:int, h:int):void {
			this.w = w;
			this.h = h;
			fixLayout();
		}
	
		protected function fixLayout():void {
			// cursor tool buttons
			var space:int = 3;
//			copyTool.x = 760+(app.stageIsContracted?ApplicationManager.sharedManager().contractedOffsetX:0);
			if(app.stageIsHided){
				copyTool.x = 280;
			}else if(app.stageIsContracted){
				copyTool.x = 520;
			}else{
				copyTool.x = 760;
			}
			cutTool.x = copyTool.right() + space;
			growTool.x = cutTool.right() + space;
			shrinkTool.x = growTool.right() + space;
			connectTool.x = shrinkTool.right() + 10;
			copyTool.y = cutTool.y = shrinkTool.y = growTool.y = connectTool.y = 4;

			mcNotice.x = connectTool.right() + 10;
			mcNotice.y = 5;
		}
	
		public function refresh():void {
			fixLayout();
		}
	
		private function onClickLink(evt:MouseEvent):void{
			ConnectionManager.sharedManager().onConnect("upgrade_firmware");
		}
		protected function addTextButtons():void {
			addChild(mcNotice);
			mcNotice.addChild(offlineNotice);
			mcNotice.addEventListener(MouseEvent.CLICK,onClickLink); 
			mcNotice.buttonMode = true;
			mcNotice.useHandCursor = true;
			mcNotice.mouseChildren = false;
			mcNotice.mouseEnabled = true;
			offlineNotice.visible = true;
			offlineNotice.autoSize = TextFieldAutoSize.LEFT;
			offlineNotice.defaultTextFormat = new TextFormat(CSS.font, 12, 0x000000);
			offlineNotice.text = Translator.map('Unknown Firmware');
			offlineNotice.selectable = false;
		}
	
		private function addToolButtons():void {
			function selectTool(b:IconButton):void {
				var newTool:String = '';
				if (b == copyTool) newTool = 'copy';
				if (b == cutTool) newTool = 'cut';
				if (b == growTool) newTool = 'grow';
				if (b == shrinkTool) newTool = 'shrink';
			//	if (b == helpTool) newTool = 'help';
				if (newTool == toolOnMouseDown) {
					clearToolButtons();
					CursorTool.setTool(null);
				} else {
					clearToolButtonsExcept(b);
					CursorTool.setTool(newTool);
				}
			}

			function selectTool2():void {
				connectTool.turnOff();
				if(ConnectionManager.sharedManager().isConnected) {
					ConnectionManager.sharedManager().onClose();
				} else {
					var arr:Array = ConnectionManager.sharedManager().portlist;
					if(arr.length>0) {
						ConnectionManager.sharedManager().onOpen(arr[0]);
					}
				}
			}

			addChild(copyTool		= makeToolButton('copyTool', selectTool));
			addChild(cutTool		= makeToolButton('cutTool', selectTool));
			addChild(growTool		= makeToolButton('growTool', selectTool));
			addChild(shrinkTool		= makeToolButton('shrinkTool', selectTool));
			addChild(connectTool	= new IconButton(selectTool2, 'connect'));
	
			SimpleTooltips.add(copyTool,    {text: 'Duplicate', direction: 'bottom'});
			SimpleTooltips.add(cutTool,     {text: 'Delete',    direction: 'bottom'});
			SimpleTooltips.add(growTool,    {text: 'Grow',      direction: 'bottom'});
			SimpleTooltips.add(shrinkTool,  {text: 'Shrink',    direction: 'bottom'});
			SimpleTooltips.add(connectTool, {text: 'Connect',   direction: 'bottom'});
		}
	
		public function clearToolButtons():void { clearToolButtonsExcept(null) }
	
		private function clearToolButtonsExcept(activeButton: IconButton):void {
			for each (var b:IconButton in [copyTool, cutTool, growTool, shrinkTool]) {
				if (b != activeButton) b.turnOff();
			}
		}
	
		private function makeToolButton(iconName:String, fcn:Function):IconButton {
			function mouseDown(evt:MouseEvent):void { toolOnMouseDown = CursorTool.tool }
			var onImage:Sprite = toolButtonImage(iconName, 0xcfefff, 1);
			var offImage:Sprite = toolButtonImage(iconName, 0, 0);
			var b:IconButton = new IconButton(fcn, onImage, offImage);
			b.actOnMouseUp();
			b.addEventListener(MouseEvent.MOUSE_DOWN, mouseDown); // capture tool on mouse down to support deselecting
			return b;
		}
	
		private function toolButtonImage(iconName:String, color:int, alpha:Number):Sprite {
			const w:int = 23;
			const h:int = 24;
			var img:Bitmap;
			var result:Sprite = new Sprite();
			var g:Graphics = result.graphics;
			g.clear();
			g.beginFill(color, alpha);
			g.drawRoundRect(0, 0, w, h, 8, 8);
			g.endFill();
			result.addChild(img = Resources.createBmp(iconName));
			img.x = Math.floor((w - img.width) / 2);
			img.y = Math.floor((h - img.height) / 2);
			return result;
		}
	
		protected function makeButtonImg(s:String, c:int, isOn:Boolean):Sprite {
			var result:Sprite = new Sprite();
	
			var label:TextField = makeLabel(Translator.map(s), CSS.topBarButtonFormat, 2, 2);
			label.textColor = CSS.white;
			label.x = 6;
			result.addChild(label); // label disabled for now
	
			var w:int = label.textWidth + 16;
			var h:int = 22;
			var g:Graphics = result.graphics;
			g.clear();
			g.beginFill(c);
			g.drawRoundRect(0, 0, w, h, 8, 8);
			g.endFill();
	
			return result;
		}
		public function setConnectedTitle(title:String):void{
			offlineNotice.text = Translator.map('Unknown Firmware');
			AppTitleMgr.Instance.setConnectInfo(title);
			if(title == "Connect")
				connectTool.turnOn();
			else
				connectTool.turnOff();
		}
		public function setBoardTitle():void{
		}
		public function setDisconnectedTitle():void{
			setConnectedTitle(null);
		}
	}
}
