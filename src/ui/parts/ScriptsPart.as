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

// ScriptsPart.as
// John Maloney, November 2011
//
// This part holds the palette and scripts pane for the current sprite (or stage).

package ui.parts {
	import flash.display.Bitmap;
	import flash.display.Graphics;
	import flash.display.Shape;
	import flash.display.Sprite;
	import flash.events.Event;
	import flash.events.MouseEvent;
	import flash.html.HTMLLoader;
	import flash.net.URLRequest;
	import flash.system.ApplicationDomain;
	import flash.text.TextField;
	import flash.text.TextFormat;
	import flash.utils.ByteArray;
	import flash.utils.getTimer;
	
	import blocks.Block;
	
	import cc.makeblock.util.HexUtil;
	
	import extensions.ArduinoManager;
	import extensions.ConnectionManager;
	
	import scratch.ScratchObj;
	import scratch.ScratchSprite;
	import scratch.ScratchStage;
	
	import translation.Translator;
	
	import ui.BlockPalette;
	import ui.PaletteSelector;
	
	import uiwidgets.Button;
	import uiwidgets.DialogBox;
	import uiwidgets.IndicatorLight;
	import uiwidgets.ScriptsPane;
	import uiwidgets.ScrollFrame;
	import uiwidgets.ZoomWidget;
	
	import util.JSON;

public class ScriptsPart extends UIPart {
	
	private var shape:Shape;
	public var selector:PaletteSelector;
	private var spriteWatermark:Bitmap;

	private var paletteFrame:ScrollFrame;
	private var paletteIndex:int;

	private var scriptsFrame:ScrollFrame;
	private var zoomWidget:ZoomWidget;

	private var arduinoFrame:ScrollFrame;
	private var uploadBt:Button = new Button(Translator.map("Upload to Arduino"));
	private var openBt:Button = new Button(Translator.map("Open with Arduino IDE"));
	private var htmlLoader:HTMLLoader;
	
	private var arduinoCodeText:String = "";
	
	public function ScriptsPart(app:Main) {
		this.app = app;

		addChild(shape = new Shape());
		addChild(spriteWatermark = new Bitmap());
		addXYDisplay();
		addChild(selector = new PaletteSelector(app));

		var palette:BlockPalette = new BlockPalette();
		palette.color = CSS.tabColor;
		paletteFrame = new ScrollFrame();
		paletteFrame.allowHorizontalScrollbar = false;
		paletteFrame.setContents(palette);
		addChild(paletteFrame);
		paletteFrame.addEventListener(MouseEvent.ROLL_OVER, __onMouseOver);
		paletteFrame.addEventListener(MouseEvent.ROLL_OUT, __onMouseOut);
		paletteIndex = getChildIndex(paletteFrame);

		var scriptsPane:ScriptsPane = new ScriptsPane(app);
		scriptsFrame = new ScrollFrame(true);
		scriptsFrame.setContents(scriptsPane);
		addChild(scriptsFrame);
		app.palette = palette;
		app.scriptsPane = scriptsPane;
		addChild(zoomWidget = new ZoomWidget(scriptsPane));
		
		// arduinoFrame / uploadBt / openBt / htmlLoader
		arduinoFrame = new ScrollFrame(false);
		arduinoFrame.visible = false;
		uploadBt.x = 70;
		uploadBt.y = 10;
		uploadBt.addEventListener(MouseEvent.CLICK,onCompileArduino);
		arduinoFrame.addChild(uploadBt);

		openBt.y = 10;
		openBt.addEventListener(MouseEvent.CLICK,onOpenArduinoIDE);
		arduinoFrame.addChild(openBt);
		addChild(arduinoFrame);

		htmlLoader = new HTMLLoader();
		htmlLoader.placeLoadStringContentInApplicationSandbox = true;
		htmlLoader.runtimeApplicationDomain = ApplicationDomain.currentDomain;
		htmlLoader.load(new URLRequest("assets/html/index.html"));
		addChild(htmlLoader);
	}
	
	private var maskWidth:int;

	private function __onMouseOver(event:MouseEvent):void
	{
		setChildIndex(paletteFrame, numChildren-1);
		paletteFrame.addEventListener(Event.ENTER_FRAME, __onEnterFrame);
		maskWidth = 0;
	}
	
	private function __onEnterFrame(event:Event):void
	{
		if(maskWidth < 1200){
			maskWidth += 30;
			paletteFrame.showRightPart(maskWidth);
		}
		if(paletteFrame.mouseX > BlockPalette.WIDTH){
			__onMouseOut(null);
		}
	}
	
	private function __onMouseOut(event:MouseEvent):void
	{
		paletteFrame.removeEventListener(Event.ENTER_FRAME, __onEnterFrame);
		paletteFrame.hideRightPart();
		setChildIndex(paletteFrame, paletteIndex);
	}
	public function appendMessage(msg:String):void{
		htmlLoader.window.appendInfo(msg+"\n");
		Main.app.track(msg);
	}
	public function appendRawMessage(msg:String):void{
		htmlLoader.window.appendInfo(msg);
		Main.app.track(msg);//.replace("\r","").replace("\n",""));
	}
	public function clearInfo():void
	{
		htmlLoader.window.clearInfo();
	}
	
	public function onSerialSend(bytes:ByteArray):void
	{
		appendMsgWithTimestamp(HexUtil.bytesToString(bytes), true);
	}

	public function onSerialDataReceived(bytes:ByteArray):void{
		appendMsgWithTimestamp(HexUtil.bytesToString(bytes), false);
	}
	
	public function appendMsgWithTimestamp(msg:String, isOut:Boolean):void
	{
		var sendType:String = isOut ? " > " : " < ";
		appendMessage(formatTime() + sendType + msg);
	}
	
	static private function formatTime():String
	{
		var date:Date = new Date();
		return formatStr(date.hours.toString()  , 2) + ":"
			 + formatStr(date.minutes.toString(), 2) + ":"
			 + formatStr(date.seconds.toString(), 2) + "."
			 + formatStr(date.milliseconds.toString(), 3);
	}
	
	static private function formatStr(str:String, len:int):String
	{
		while(str.length < len){
			str = "0" + str;
		}
		return str;
	}
	public function get isArduinoMode():Boolean{
		return arduinoFrame.visible;
	}
	private function onCompileArduino(evt:MouseEvent):void{
		//if(SerialManager.sharedManager().isConnected){
		if(ConnectionManager.sharedManager().selectPort!=""){
			if(ArduinoManager.sharedManager().isUploading==false){
				htmlLoader.window.clearInfo();
				if(showArduinoCode()){
					htmlLoader.window.appendInfo(ArduinoManager.sharedManager().UploadToArduino(arduinoCodeText));
					ConnectionManager.sharedManager().onClose();
				}
			}
		}else{
			var dialog:DialogBox = new DialogBox();
			dialog.addTitle("Message");
			dialog.addText("Please connect the serial port.");
			function onCancel():void{
				dialog.cancel();
			}
			dialog.addButton("OK",onCancel);
			dialog.showOnStage(app.stage);
		}
	}

	private function onOpenArduinoIDE(evt:MouseEvent):void{
		if(showArduinoCode()){
			ArduinoManager.sharedManager().openArduinoIDE(arduinoCodeText);
		}
	}
	
	static private var isDialogBoxShowing:Boolean;
	public function showArduinoCode(arg:String=""):Boolean{
		var retcode:String = "";
		try{
			retcode = util.JSON.stringify(app.stagePane);
		}catch(e:*){
			return false;
		}

		var formatCode:String = ArduinoManager.sharedManager().jsonToCpp(retcode);
		if(formatCode==null){
			return false;
		}
		uploadBt.visible = !ArduinoManager.sharedManager().hasUnknownCode;

		if(!app.stageIsArduino){
			app.toggleArduinoMode();
		}
		for(var i:uint=0;i<5;i++){
			formatCode = formatCode.split("\r\n\r\n").join("\r\n").split("\r\n\t\r\n").join("\r\n");
		}
		arduinoCodeText = formatCode;
		
		htmlLoader.window.setCode(arduinoCodeText);
		
		fixlayout();
		if(ArduinoManager.sharedManager().hasUnknownCode){
			if(!isDialogBoxShowing){
				isDialogBoxShowing = true;
				var dBox:DialogBox = new DialogBox();
				dBox.addTitle(Translator.map("unsupported block found, remove them to continue."));
				for each(var b:Block in ArduinoManager.sharedManager().unknownBlocks){
					b.mouseEnabled = false;
					b.mouseChildren = false;
					dBox.addBlock(b);
				}
				function cancelHandle():void{
					isDialogBoxShowing = false;
					dBox.cancel();
				}
				dBox.addButton("OK",cancelHandle);
				dBox.showOnStage(app.stage);
				dBox.fixLayout();
			}
			arduinoFrame.visible = false;
			if(app.stageIsArduino){
				app.toggleArduinoMode();
			}
		}else{
			arduinoFrame.visible = true;
		}
		htmlLoader.visible = arduinoFrame.visible;
		return true;
	}
	public function resetCategory():void {
		selector.select(Specs.myBlocksCategory)
	}

	public function updatePalette():void {
		selector.updateTranslation();
		if(!Main.app.stageIsArduino && Main.app.viewedObj() is ScratchStage){
			if(selector.selectedCategory == Specs.motionCategory){
				selector.selectedCategory = Specs.myBlocksCategory;//looksCategory;
			}
		}
		selector.select(selector.selectedCategory);
	}

	public function updateTranslation():void{
		uploadBt.setLabel(Translator.map("Upload to Arduino"));
		openBt.setLabel(Translator.map("Edit with Arduino IDE"));
	}

	public function updateSpriteWatermark():void {
		var target:ScratchObj = app.viewedObj();
		if (target && !target.isStage) {
			spriteWatermark.bitmapData = target.currentCostume().thumbnail(40, 40, false);
		} else {
			spriteWatermark.bitmapData = null;
		}
	}

	private var xyDisplay:Sprite;
	private var xLabel:TextField;
	private var yLabel:TextField;
	private var xReadout:TextField;
	private var yReadout:TextField;
	private var lastX:int = -10000000; // impossible value to force initial update
	private var lastY:int = -10000000; // impossible value to force initial update
	public function step():void {
		// Update the mouse reaadouts. Do nothing if they are up-to-date (to minimize CPU load).
		var target:ScratchObj = app.viewedObj();
		if (target.isStage) {
			if (xyDisplay.visible) xyDisplay.visible = false;
		} else {
			if (!xyDisplay.visible) xyDisplay.visible = true;

			var spr:ScratchSprite = target as ScratchSprite;
			if (!spr) return;
			if (spr.scratchX != lastX) {
				lastX = spr.scratchX;
				xReadout.text = String(lastX);
			}
			if (spr.scratchY != lastY) {
				lastY = spr.scratchY;
				yReadout.text = String(lastY);
			}
		}
		updateExtensionIndicators();
	}

	private var lastUpdateTime:uint;

	private function updateExtensionIndicators():void {
		if ((getTimer() - lastUpdateTime) < 500) return;
		for (var i:int = 0; i < app.palette.numChildren; i++) {
			var indicator:IndicatorLight = app.palette.getChildAt(i) as IndicatorLight;
			if (indicator) app.extensionManager.updateIndicator(indicator, indicator.target);
		}		
		lastUpdateTime = getTimer();
	}

	public function setWidthHeight(w:int, h:int):void {
		this.w = w;
		this.h = h;
		fixlayout();
		redraw();
	}

	private function fixlayout():void {
		selector.x = 1;
		selector.y = 5;
		paletteFrame.x = selector.x;
		paletteFrame.y = selector.y + selector.height + 2;
		paletteFrame.setWidthHeight(selector.width + 1, h - paletteFrame.y - 2); // 模块滚动区域宽度
		scriptsFrame.x = selector.x + selector.width + 2;
		scriptsFrame.y = selector.y + 1;

		var arduinoWidth:uint = app.stageIsArduino?(w/2-150):0;
		var arduinoHeight:uint = h - 10;
		arduinoFrame.visible = app.stageIsArduino;
		scriptsFrame.setWidthHeight(w - scriptsFrame.x - 15-arduinoWidth, h - scriptsFrame.y - 5);//代码区
		arduinoFrame.x = scriptsFrame.x+ (w - scriptsFrame.x - 15-arduinoWidth)+8;
		arduinoFrame.y = scriptsFrame.y;
		arduinoFrame.setWidthHeight(arduinoWidth, arduinoHeight);
		htmlLoader.visible = arduinoFrame.visible;
		htmlLoader.x = arduinoFrame.x;
		htmlLoader.y = arduinoFrame.y + 40;
		htmlLoader.width = arduinoWidth;
		htmlLoader.height = arduinoHeight - 40;
		openBt.x = arduinoWidth - openBt.width - 10;
		spriteWatermark.x = w - arduinoWidth - 60;
		spriteWatermark.y = scriptsFrame.y + 10;
		xyDisplay.x = spriteWatermark.x + 1;
		xyDisplay.y = spriteWatermark.y + 43;
		zoomWidget.x = w - arduinoWidth - zoomWidget.width - 30;
		zoomWidget.y = h - zoomWidget.height - 15;
	}

	private function redraw():void {
		var paletteW:int = paletteFrame.visibleW();
		var paletteH:int = paletteFrame.visibleH();
		var scriptsW:int = scriptsFrame.visibleW();
		var scriptsH:int = scriptsFrame.visibleH();

		var g:Graphics = shape.graphics;
		g.clear();
		g.lineStyle(1, CSS.borderColor, 1, true);
		g.beginFill(CSS.tabColor);
		g.drawRect(0, 0, w, h);
		g.endFill();

		var lineY:int = selector.y + selector.height;
		var darkerBorder:int = CSS.borderColor - 0x141414;
		var lighterBorder:int = 0xF2F2F2;
		g.lineStyle(1, darkerBorder, 1, true);
		hLine(g, paletteFrame.x + 8, lineY, paletteW - 20);
		g.lineStyle(1, lighterBorder, 1, true);
		hLine(g, paletteFrame.x + 8, lineY + 1, paletteW - 20);

		g.lineStyle(1, darkerBorder, 1, true);
		g.drawRect(scriptsFrame.x - 1, scriptsFrame.y - 1, scriptsW + 1, scriptsH + 1);
	}

	private function hLine(g:Graphics, x:int, y:int, w:int):void {
		g.moveTo(x, y);
		g.lineTo(x + w, y);
	}

	private const readoutLabelFormat:TextFormat = new TextFormat(CSS.font, 12, CSS.textColor, true);
	private const readoutFormat:TextFormat = new TextFormat(CSS.font, 12, CSS.textColor);
	private function addXYDisplay():void {
		xyDisplay = new Sprite();
		xyDisplay.addChild(xLabel = makeLabel('x:', readoutLabelFormat, 0, 0));
		xyDisplay.addChild(xReadout = makeLabel('-888', readoutFormat, 15, 0));
		xyDisplay.addChild(yLabel = makeLabel('y:', readoutLabelFormat, 0, 13));
		xyDisplay.addChild(yReadout = makeLabel('-888', readoutFormat, 15, 13));
		addChild(xyDisplay);
	}
}}
