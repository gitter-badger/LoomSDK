// =================================================================================================
//
//	Starling Framework
//	Copyright 2011 Gamua OG. All Rights Reserved.
//
//	This program is free software. You can redistribute and/or modify it
//	in accordance with the terms of the accompanying license agreement.
//
// =================================================================================================

package loom2d.core
{
    import loom2d.display.CCLayer;
    import loom.Application;

    import loom2d.math.Point;
    
    import loom2d.display.Stage;
    import loom2d.display.DisplayObject;
    import loom2d.events.KeyboardEvent;
    import loom2d.events.EventDispatcher;
    import loom2d.events.Touch;
    import loom2d.events.TouchEvent;
    import loom2d.events.TouchPhase;

    /** @private
     *  The TouchProcessor is used internally to convert mouse and touch events of the conventional
     *  Flash stage to Starling's TouchEvents. */
    public class TouchProcessor
    {
        private static const MULTITAP_TIME:Number = 0.3;
        private static const MULTITAP_DISTANCE:Number = 25;
        
        private var mStage:Stage;
        private var mRootLayer:CCLayer;
        private var mElapsedTime:Number;
        private var mTouchMarker:TouchMarker;
        
        private var mCurrentTouches:Vector.<Touch>;
        private var mQueue:Vector.<Vector.<Object>>;
        private var mLastTaps:Vector.<Touch>;
        
        private var mShiftDown:Boolean = false;
        private var mCtrlDown:Boolean = false;
        
        /** Helper objects. */
        private static var sProcessedTouchIDs:Vector.<int> = new Vector.<int>[];
        private static var sHoveringTouchData:Vector.<TouchProcessorNote> = new Vector.<TouchProcessorNote>[];
        
        public function TouchProcessor(stage:Stage, rootLayer:CCLayer)
        {
            mStage = stage;
            mRootLayer = rootLayer;
            mElapsedTime = 0.0;
            mCurrentTouches = new Vector.<Touch>[];
            mQueue = new Vector.<Array>[];
            mLastTaps = new Vector.<Touch>[];
            
            mRootLayer.onTouchBegan += handleTouchBegan;
            mRootLayer.onTouchMoved += handleTouchMoved;
            mRootLayer.onTouchEnded += handleTouchEnded;
            mRootLayer.onTouchCancelled += handleTouchEnded;

            mStage.addEventListener(KeyboardEvent.KEY_UP, onKey);
            mStage.addEventListener(KeyboardEvent.KEY_DOWN, onKey);

            monitorInterruptions(true);
        }

        protected function handleTouchBegan(id:int, x:Number, y:Number):void
        {
            // translate to stage space            
            x-=mStage.x;
            y-=mStage.y;
            x/=mStage.scaleX;
            y/=mStage.scaleY;

            enqueue(id, TouchPhase.BEGAN, x, y);
        }

        protected function handleTouchMoved(id:int, x:Number, y:Number):void
        {
            // translate to stage space            
            x-=mStage.x;
            y-=mStage.y;
            x/=mStage.scaleX;
            y/=mStage.scaleY;
            enqueue(id, TouchPhase.MOVED, x, y);
        }

        protected function handleTouchEnded(id:int, x:Number, y:Number):void
        {
            // translate to stage space            
            x-=mStage.x;
            y-=mStage.y;
            x/=mStage.scaleX;
            y/=mStage.scaleY;
            enqueue(id, TouchPhase.ENDED, x, y);
        }

        public function dispose():void
        {
            monitorInterruptions(false);

            mStage.removeEventListener(KeyboardEvent.KEY_UP, onKey);
            mStage.removeEventListener(KeyboardEvent.KEY_DOWN, onKey);

            if (mTouchMarker) mTouchMarker.dispose();
        }
        
        public function advanceTime(passedTime:Number):void
        {
            var i:int;
            var touchID:int;
            var touch:Touch;
            
            mElapsedTime += passedTime;
            
            // remove old taps
            if (mLastTaps.length > 0)
            {
                for (i=mLastTaps.length-1; i>=0; --i)
                    if (mElapsedTime - mLastTaps[i].timestamp > MULTITAP_TIME)
                        mLastTaps.splice(i, 1);
            }
            
            while (mQueue.length > 0)
            {                
                sProcessedTouchIDs.length = sHoveringTouchData.length = 0;
                
                // set touches that were new or moving to phase 'stationary'
                for each (touch in mCurrentTouches)
                    if (touch.phase == TouchPhase.BEGAN || touch.phase == TouchPhase.MOVED)
                        touch.setPhase(TouchPhase.STATIONARY);
                
                // process new touches, but each ID only once
                while (mQueue.length > 0 && 
                    sProcessedTouchIDs.indexOf(mQueue[mQueue.length-1][0]) == -1)
                {
                    var touchArgs:Vector.<Object> = mQueue.pop();
                    touchID = touchArgs[0] as int;
                    touch = getCurrentTouch(touchID);
                    
                    // hovering touches need special handling (see below)
                    if (touch && touch.phase == TouchPhase.HOVER && touch.target)
                        sHoveringTouchData.push(new TouchProcessorNote(touch, touch.target, touch.bubbleChain));
                    
                    processTouch.apply(this, touchArgs);
                    sProcessedTouchIDs.push(touchID);
                }
                
                // the same touch event will be dispatched to all targets; 
                // the 'dispatch' method will make sure each bubble target is visited only once.
                var touchEvent:TouchEvent = 
                    new TouchEvent(TouchEvent.TOUCH, mCurrentTouches, mShiftDown, mCtrlDown); 
                
                // if the target of a hovering touch changed, we dispatch the event to the previous
                // target to notify it that it's no longer being hovered over.
                for each (var touchData:TouchProcessorNote in sHoveringTouchData)
                {
                    if (touchData.touch.target != touchData.target)
                    {
                        touchEvent.dispatch(touchData.bubbleChain);
                    }
                }
                
                // dispatch events
                for each (touchID in sProcessedTouchIDs)
                {
                    getCurrentTouch(touchID).dispatchEvent(touchEvent);
                }
                
                // remove ended touches
                for (i=mCurrentTouches.length-1; i>=0; --i)
                    if (mCurrentTouches[i].phase == TouchPhase.ENDED)
                        mCurrentTouches.splice(i, 1);
            }
        }
        
        public function enqueue(touchID:int, phase:String, globalX:Number, globalY:Number,
                                pressure:Number=1.0, width:Number=1.0, height:Number=1.0):void
        {
            mQueue.unshift([touchID, phase, globalX, globalY, pressure, width, height]);
            
            // multitouch simulation (only with mouse)
            if (mCtrlDown && simulateMultitouch && touchID == 0) 
            {
                mTouchMarker.moveMarker(globalX, globalY, mShiftDown);
                mQueue.unshift([1, phase, mTouchMarker.mockX, mTouchMarker.mockY]);
            }
        }
        
        public function enqueueMouseLeftStage():void
        {
            var mouse:Touch = getCurrentTouch(0);
            if (mouse == null || mouse.phase != TouchPhase.HOVER) return;
            
            // On OS X, we get mouse events from outside the stage; on Windows, we do not.
            // This method enqueues an artifial hover point that is just outside the stage.
            // That way, objects listening for HOVERs over them will get notified everywhere.
            
            var offset:int = 1;
            var exitX:Number = mouse.globalX;
            var exitY:Number = mouse.globalY;
            var distLeft:Number = mouse.globalX;
            var distRight:Number = mStage.stageWidth - distLeft;
            var distTop:Number = mouse.globalY;
            var distBottom:Number = mStage.stageHeight - distTop;
            var minDist:Number = Math.min(distLeft, distRight, distTop, distBottom);
            
            // the new hover point should be just outside the stage, near the point where
            // the mouse point was last to be seen.
            
            if (minDist == distLeft)       exitX = -offset;
            else if (minDist == distRight) exitX = mStage.stageWidth + offset;
            else if (minDist == distTop)   exitY = -offset;
            else                           exitY = mStage.stageHeight + offset;
            
            enqueue(0, TouchPhase.HOVER, exitX, exitY);
        }
        
        private function processTouch(touchID:int, phase:String, globalX:Number, globalY:Number,
                                      pressure:Number=1.0, width:Number=1.0, height:Number=1.0):void
        {
            var position:Point = new Point(globalX, globalY);
            var touch:Touch = getCurrentTouch(touchID);
            
            if (touch == null)
            {
                touch = new Touch(touchID, globalX, globalY, phase, null);
                addCurrentTouch(touch);
            }
            
            touch.setPosition(globalX, globalY);
            touch.setPhase(phase);
            touch.setTimestamp(mElapsedTime);
            touch.setPressure(pressure);
            touch.setSize(width, height);
            
            if (phase == TouchPhase.HOVER || phase == TouchPhase.BEGAN)
            {
                var hitResult = mStage.hitTest(position, true);
                touch.setTarget(hitResult);
            }
            
            if (phase == TouchPhase.BEGAN)
                processTap(touch);
        }
        
        private function onKey(event:KeyboardEvent):void
        {
            if (event.keyCode == 17 || event.keyCode == 15) // ctrl or cmd key
            {
                var wasCtrlDown:Boolean = mCtrlDown;
                mCtrlDown = event.type == KeyboardEvent.KEY_DOWN;
                
                if (simulateMultitouch && wasCtrlDown != mCtrlDown)
                {
                    mTouchMarker.visible = mCtrlDown;
                    mTouchMarker.moveCenter(mStage.stageWidth/2, mStage.stageHeight/2);
                    
                    var mouseTouch:Touch = getCurrentTouch(0);
                    var mockedTouch:Touch = getCurrentTouch(1);
                    
                    if (mouseTouch)
                        mTouchMarker.moveMarker(mouseTouch.globalX, mouseTouch.globalY);
                    
                    // end active touch ...
                    if (wasCtrlDown && mockedTouch && mockedTouch.phase != TouchPhase.ENDED)
                        mQueue.unshift([1, TouchPhase.ENDED, mockedTouch.globalX, mockedTouch.globalY]);
                    // ... or start new one
                    else if (mCtrlDown && mouseTouch)
                    {
                        if (mouseTouch.phase == TouchPhase.HOVER || mouseTouch.phase == TouchPhase.ENDED)
                            mQueue.unshift([1, TouchPhase.HOVER, mTouchMarker.mockX, mTouchMarker.mockY]);
                        else
                            mQueue.unshift([1, TouchPhase.BEGAN, mTouchMarker.mockX, mTouchMarker.mockY]);
                    }
                }
            }
            else if (event.keyCode == 16) // shift key 
            {
                mShiftDown = event.type == KeyboardEvent.KEY_DOWN;
            }
        }
        
        private function processTap(touch:Touch):void
        {
            var nearbyTap:Touch = null;
            var minSqDist:Number = MULTITAP_DISTANCE * MULTITAP_DISTANCE;
            
            for each (var tap:Touch in mLastTaps)
            {
                var sqDist:Number = Math.pow(tap.globalX - touch.globalX, 2) +
                                    Math.pow(tap.globalY - touch.globalY, 2);
                if (sqDist <= minSqDist)
                {
                    nearbyTap = tap;
                    break;
                }
            }
            
            if (nearbyTap)
            {
                touch.setTapCount(nearbyTap.tapCount + 1);
                mLastTaps.splice(mLastTaps.indexOf(nearbyTap), 1);
            }
            else
            {
                touch.setTapCount(1);
            }
            
            mLastTaps.push(touch.clone());
        }
        
        private function addCurrentTouch(touch:Touch):void
        {
            for (var i:int=mCurrentTouches.length-1; i>=0; --i)
                if (mCurrentTouches[i].id == touch.id)
                    mCurrentTouches.splice(i, 1);
            
            mCurrentTouches.push(touch);
        }
        
        private function getCurrentTouch(touchID:int):Touch
        {
            for each (var touch:Touch in mCurrentTouches)
                if (touch.id == touchID) return touch;
            return null;
        }
        
        public function get simulateMultitouch():Boolean { return mTouchMarker != null; }
        public function set simulateMultitouch(value:Boolean):void
        { 
            if (simulateMultitouch == value) return; // no change
            if (value)
            {
                mTouchMarker = new TouchMarker();
                mTouchMarker.visible = false;
                mStage.addChild(mTouchMarker);
            }
            else
            {                
                mTouchMarker.removeFromParent(true);
                mTouchMarker = null;
            }
        }
        
        // interruption handling
        
        private function monitorInterruptions(enable:Boolean):void
        {
            // if the application moves into the background or is interrupted (e.g. through
            // an incoming phone call), we need to abort all touches.
            Application.applicationActivated += onInterruption;
            Application.applicationDeactivated += onInterruption;
        }
        
        private function onInterruption():void
        {
            var touch:Touch;
            
            // abort touches
            for each (touch in mCurrentTouches)
            {
                if (touch.phase == TouchPhase.BEGAN || touch.phase == TouchPhase.MOVED ||
                    touch.phase == TouchPhase.STATIONARY)
                {
                    touch.setPhase(TouchPhase.ENDED);
                }
            }
            
            // dispatch events
            var touchEvent:TouchEvent = 
                new TouchEvent(TouchEvent.TOUCH, mCurrentTouches, mShiftDown, mCtrlDown);
            
            for each (touch in mCurrentTouches)
                touch.dispatchEvent(touchEvent);
            
            // purge touches
            mCurrentTouches.length = 0;
        }
    }

    /** @private
     * Internal helper for TouchProcessor to keep track of event dispatch details in the presence of
     * of a changing EventDispatcher hierarchy.
     */
    public class TouchProcessorNote
    {
        public function TouchProcessorNote(t:Touch, targ:EventDispatcher, chain:Vector.<EventDispatcher>)
        {
            touch = t;
            target = targ;
            bubbleChain = chain;
        }

        public var touch:Touch;
        public var target:EventDispatcher;
        public var bubbleChain:Vector.<EventDispatcher>;
    }
}
