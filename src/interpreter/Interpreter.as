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

// Interpreter.as
// John Maloney, August 2009
// Revised, March 2010
//
// A simple yet efficient interpreter for blocks.
//
// Interpreters may seem mysterious, but this one is quite straightforward. Since every
// block knows which block (if any) follows it in a sequence of blocks, the interpreter
// simply executes the current block, then asks that block for the next block. The heart
// of the interpreter is the evalCmd() function, which looks up the opcode string in a
// dictionary (initialized by initPrims()) then calls the primitive function for that opcode.
// Control structures are handled by pushing the current state onto the active thread's
// execution stack and continuing with the first block of the substack. When the end of a
// substack is reached, the previous execution state is popped. If the substack was a loop
// body, control yields to the next thread. Otherwise, execution continues with the next
// block. If there is no next block, and no state to pop, the thread terminates.
//
// The interpreter does as much as it can within workTime milliseconds, then returns
// control. It returns control earlier if either (a) there are are no more threads to run
// or (b) some thread does a command that has a visible effect (e.g. "move 10 steps").
//
// To add a command to the interpreter, just add a new case to initPrims(). Command blocks
// usually perform some operation and return null, while reporters must return a value.
// Control structures are a little tricky; look at some of the existing control structure
// commands to get a sense of what to do.
//
// Clocks and time:
//
// The millisecond clock starts at zero when Flash is started and, since the clock is
// a 32-bit integer, it wraps after 24.86 days. Since it seems unlikely that one Scratch
// session would run that long, this code doesn't deal with clock wrapping.
// Since Scratch only runs at discrete intervals, timed commands may be resumed a few
// milliseconds late. These small errors accumulate, causing threads to slip out of
// synchronization with each other, a problem especially noticable in music projects.
// This problem is addressed by recording the amount of time slipage and shortening
// subsequent timed commmands slightly to "catch up".
// Delay times are rounded to milliseconds, and the minimum delay is a millisecond.

package interpreter {
	import flash.geom.Point;
	import flash.utils.getTimer;
	
	import blockly.runtime.Thread;
	
	import blocks.Block;
	
	import cc.makeblock.interpreter.BlockInterpreter;
	import cc.makeblock.interpreter.RemoteCallMgr;
	
	import scratch.ScratchObj;
	
public class Interpreter {

	private var _currentMSecs:int;	// millisecond clock for the current step
	public var turboMode:Boolean;
	private var app:Main;

	public function Interpreter(app:Main) {
		this.app = app;
		_currentMSecs = getTimer();
		RemoteCallMgr.Instance.init();
	}
	
	public function get currentMSecs():int
	{
		return _currentMSecs;
	}

	/* Threads */

	public function hasThreads():Boolean
	{
		return BlockInterpreter.Instance.hasTheadsRunning();
	}
	
	static private const zeroPt:Point = new Point();
	
	public function runThread(b:Block, targetObj:ScratchObj):Thread
	{
		var thread:Thread = BlockInterpreter.Instance.execute(b, targetObj);
		thread.finishSignal.add(function(isInterput:Boolean):void{
			b.hideRunFeedback();
			var p:Point = b.localToGlobal(zeroPt);
			switch(b.type.toLowerCase()){
				case "r":
					Main.app.showBubble(thread.resultValue, p.x, p.y, b.width);
					break;
				case "b":
					Main.app.showBubble(Boolean(thread.resultValue).toString(), p.x, p.y, b.width);
					break;
			}
		}, true);
		b.showRunFeedback();
		app.threadStarted();
		return thread;
	}

	public function toggleThread(b:Block, targetObj:ScratchObj, startupDelay:int = 0):Thread {
		if(BlockInterpreter.Instance.isRunning(b, targetObj)){
			BlockInterpreter.Instance.stopThread(b, targetObj);
			if(app.editMode) b.hideRunFeedback();
			return null;
		}
		return runThread(b, targetObj);
	}

	public function isRunning(b:Block, targetObj:ScratchObj):Boolean {
		return BlockInterpreter.Instance.isRunning(b, targetObj);
	}

	public function startThreadForClone(b:Block, clone:*):void {
		toggleThread(b, clone);
	}

	public function stopThreadsFor(target:*, skipActiveThread:Boolean = false):void {
		BlockInterpreter.Instance.stopObjAllThreads(target);
	}

	public function restartThread(b:Block, targetObj:*):void {
		BlockInterpreter.Instance.stopThread(b, targetObj);
		runThread(b, targetObj);
	}

	public function stopAllThreads():void {
//		threads.length = 0;
		BlockInterpreter.Instance.stopAllThreads();
		app.runtime.clearRunFeedback();
	}
	
	public function stepThreads():void {
		_currentMSecs = getTimer();
	}

	/* Evaluation */

	public static function asNumber(n:*):Number {
		// Convert n to a number if possible. If n is a string, it must contain
		// at least one digit to be treated as a number (otherwise a string
		// containing only whitespace would be consider equal to zero.)
		if (n is String) {
			var s:String = n as String;
			var len:uint = s.length;
			for (var i:int = 0; i < len; i++) {
				var code:uint = s.charCodeAt(i);
				if (code >= 48 && code <= 57) return Number(s);
			}
			return NaN; // no digits found; string is not a number
		}
		return Number(n);
	}

	/* Primitives */

	public function isImplemented(op:String):Boolean {
		return true;
	}
	
	public function execBlock(op:String, block:Block):*
	{
		return 0;
	}

	// Procedure call/return
}
}
