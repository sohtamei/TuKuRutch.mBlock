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
		private var connectButton:IconButton;
		private var activeTool:String;
	
		private var versionSprite:Sprite = new Sprite;
		public  var versionText:TextField = new TextField;
	
		public function TopBarPart(app:Main) {
			this.app = app;

			addChild(versionSprite);
			versionSprite.addChild(versionText);
			versionSprite.addEventListener(MouseEvent.CLICK, onClickLink); 
			versionSprite.buttonMode = true;
			versionSprite.useHandCursor = true;
			versionSprite.mouseChildren = false;
			versionSprite.mouseEnabled = true;
			versionText.visible = true;
			versionText.autoSize = TextFieldAutoSize.LEFT;
			versionText.defaultTextFormat = new TextFormat(CSS.font, 12, 0x000000);
			versionText.text = Translator.map('Unknown Firmware');
			versionText.selectable = false;

			addChild(copyTool		= makeToolButton('copyTool', selectTool));
			addChild(cutTool		= makeToolButton('cutTool', selectTool));
			addChild(growTool		= makeToolButton('growTool', selectTool));
			addChild(shrinkTool		= makeToolButton('shrinkTool', selectTool));

			addChild(connectButton	= new IconButton(selectTool2, 'connect'));
	
			SimpleTooltips.add(copyTool,    {text: 'Duplicate', direction: 'bottom'});
			SimpleTooltips.add(cutTool,     {text: 'Delete',    direction: 'bottom'});
			SimpleTooltips.add(growTool,    {text: 'Grow',      direction: 'bottom'});
			SimpleTooltips.add(shrinkTool,  {text: 'Shrink',    direction: 'bottom'});
			SimpleTooltips.add(connectButton, {text: 'Connect',   direction: 'bottom'});

			refresh();
		}

		private function onClickLink(evt:MouseEvent):void
		{
			ConnectionManager.sharedManager().onConnect("upgrade_firmware");
		}
	
		private function makeToolButton(iconName:String, fcn:Function):IconButton
		{
			function mouseDown(evt:MouseEvent):void { activeTool = CursorTool.tool }
			var onImage:Sprite = toolButtonImage(iconName, 0xcfefff, 1);
			var offImage:Sprite = toolButtonImage(iconName, 0, 0);
			var b:IconButton = new IconButton(fcn, onImage, offImage);
			b.actOnMouseUp();
			b.addEventListener(MouseEvent.MOUSE_DOWN, mouseDown); // capture tool on mouse down to support deselecting
			return b;
		}
	
		private function selectTool(b:IconButton):void {
			var newTool:String = '';
			if (b == copyTool) newTool = 'copy';
			if (b == cutTool) newTool = 'cut';
			if (b == growTool) newTool = 'grow';
			if (b == shrinkTool) newTool = 'shrink';
			if (newTool == activeTool) {
				clearToolButtons();
				CursorTool.setTool(null);
			} else {
				clearToolButtonsExcept(b);
				CursorTool.setTool(newTool);
			}
		}

		private function selectTool2(b:IconButton):void {
			connectButton.turnOff();
			if(ConnectionManager.sharedManager().isConnected) {
				ConnectionManager.sharedManager().onClose();
			} else {
				var arr:Array = ConnectionManager.sharedManager().portlist;
				if(arr.length>0) {
					ConnectionManager.sharedManager().onOpen(arr[0]);
				}
			}
		}

		public function refresh():void {
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
			connectButton.x = shrinkTool.right() + 10;
			copyTool.y = cutTool.y = shrinkTool.y = growTool.y = connectButton.y = 4;

			versionSprite.x = connectButton.right() + 10;
			versionSprite.y = 5;
		}
/*
		protected function removeTextSprite():void {
			if (versionSprite.parent) {
				removeChild(versionSprite);
				versionSprite.removeEventListener(MouseEvent.CLICK, onClickLink); 
			}
		}
*/
		public function updateTranslation():void {
		//	removeTextSprite();
		//	addTextSprite();
			refresh();
		}

		public function setWidthHeight(w:int, h:int):void {
			this.w = w;
			this.h = h;
			refresh();
		}
	
		public function clearToolButtons():void { clearToolButtonsExcept(null) }
	
		private function clearToolButtonsExcept(activeButton: IconButton):void
		{
			for each (var b:IconButton in [copyTool, cutTool, growTool, shrinkTool]) {
				if (b != activeButton) b.turnOff();
			}
		}
	
		private function toolButtonImage(iconName:String, color:int, alpha:Number):Sprite
		{
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

		public function setConnectedButton(connected:Boolean):void
		{
			versionText.text = Translator.map('Unknown Firmware');
			if(connected)
				connectButton.turnOn();
			else
				connectButton.turnOff();
		}
	}
}
