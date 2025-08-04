//+------------------------------------------------------------------+
//|                                       SpeedBreakoutBot.mq5       |
//|                                       https://hurated.com        |
//+------------------------------------------------------------------+
#property strict

input string   InpSymbol            = "EURUSD";
input ENUM_TIMEFRAMES InpTimeframe  = PERIOD_M1;
input int      SpeedPeriod          = 50;          // Number of candles for speed average
input double   SpeedMultiplier      = 1.5;         // Multiplier over avg speed to trigger orders
input double   OrderDistancePoints  = 100;         // Distance in points from current price
input double   SL_Points            = 150;         // Stop loss in points
input double   TP_Points            = 300;         // Take profit in points
input double   LotSize              = 0.1;
input int      TradingStartHour     = 8;
input int      TradingEndHour       = 16;
input int      TimerIntervalSeconds = 30;         // Timer interval in seconds
input bool     EnableDynamicOrders  = false;      // Enable dynamic order updates (CHANGED: default false)
input int      MaxPositions         = 1;          // Maximum open positions
input int      StartupMonitorMinutes = 20;        // Monitor-only period before trading (minutes)
input int      OrderUpdateMinutes   = 5;          // Minimum minutes between order updates (NEW)
input bool     UseLastCompletedCandle = true;     // Use last completed candle for speed (NEW)

// Order tickets
ulong buyStopTicket = 0;
ulong sellStopTicket = 0;

// Position tracking
datetime lastPositionCheck = 0;
datetime botStartTime = 0;
datetime botStartTimeLocal = 0;
datetime lastOrderUpdate = 0;  // NEW: Track last order update time

//+------------------------------------------------------------------+
int OnInit() {
   // Record bot start time (both server and local)
   botStartTime = TimeCurrent();
   botStartTimeLocal = TimeLocal();
   
   // Validate inputs
   if (SpeedPeriod <= 0) {
      Print("Error: SpeedPeriod must be greater than 0");
      return INIT_PARAMETERS_INCORRECT;
   }
   
   if (TimerIntervalSeconds <= 0) {
      Print("Error: TimerIntervalSeconds must be greater than 0");
      return INIT_PARAMETERS_INCORRECT;
   }
   
   if (!EventSetTimer(TimerIntervalSeconds)) {
      Print("Error: Failed to set timer");
      return INIT_FAILED;
   }
   
   Print("SpeedBreakoutBot initialized successfully");
   Print("Timer interval: ", TimerIntervalSeconds, " seconds");
   Print("Trading hours: ", TradingStartHour, ":00 - ", TradingEndHour, ":00");
   Print("Order update frequency: ", OrderUpdateMinutes, " minutes");
   Print("Dynamic orders: ", EnableDynamicOrders ? "ENABLED" : "DISABLED");
   Print("Speed calculation using: ", UseLastCompletedCandle ? "Last completed candle" : "Current candle");
   
   datetime tradingStartTimeLocal = botStartTimeLocal + StartupMonitorMinutes * 60;
   Print("Server time: ", TimeToString(botStartTime, TIME_MINUTES));
   Print("Local time: ", TimeToString(botStartTimeLocal, TIME_MINUTES));
   Print("Startup monitoring period: ", StartupMonitorMinutes, " minutes");
   Print("Will start trading after: ", TimeToString(tradingStartTimeLocal, TIME_MINUTES), " (local time)");
   Print("Speed calculation needs ", SpeedPeriod, " historical candles (", SpeedPeriod, " minutes on M1)");
   
   return INIT_SUCCEEDED;
}
//+------------------------------------------------------------------+
void OnDeinit(const int reason) {
   EventKillTimer();
   CancelOrders(); // Clean up on shutdown
   Print("SpeedBreakoutBot deinitialized. Reason: ", reason);
}
//+------------------------------------------------------------------+
double CalculateSpeed(int shift) {
   double open = iOpen(InpSymbol, InpTimeframe, shift);
   double close = iClose(InpSymbol, InpTimeframe, shift);
   double speed = MathAbs(close - open);
   
   // Debug output for current candle
   if (shift == 0) {
      static datetime lastDebugTime = 0;
      datetime currentTime = TimeCurrent();
      if (currentTime - lastDebugTime > 60) { // Debug every minute
         Print("DEBUG Current candle (shift 0): Open=", open, ", Close=", close, ", Speed=", speed);
         Print("DEBUG Last completed candle (shift 1): Open=", iOpen(InpSymbol, InpTimeframe, 1), 
               ", Close=", iClose(InpSymbol, InpTimeframe, 1), ", Speed=", CalculateSpeedInternal(1));
         lastDebugTime = currentTime;
      }
   }
   
   return speed;
}
//+------------------------------------------------------------------+
double CalculateSpeedInternal(int shift) {
   double open = iOpen(InpSymbol, InpTimeframe, shift);
   double close = iClose(InpSymbol, InpTimeframe, shift);
   return MathAbs(close - open);
}
//+------------------------------------------------------------------+
double CalculateCurrentSpeed() {
   // IMPROVED: Allow choice between current candle and last completed candle
   if (UseLastCompletedCandle) {
      // Use last completed candle (more reliable)
      double speed = CalculateSpeed(1);
      
      static datetime lastDebugTime = 0;
      datetime currentTime = TimeCurrent();
      if (currentTime - lastDebugTime > 60) {
         Print("DEBUG Speed calculation (using last completed candle):");
         Print("  Last completed candle speed: ", speed);
         lastDebugTime = currentTime;
      }
      
      return speed;
   } else {
      // Original logic - use current candle
      double open = iOpen(InpSymbol, InpTimeframe, 0);
      double currentPrice = (SymbolInfoDouble(InpSymbol, SYMBOL_ASK) + SymbolInfoDouble(InpSymbol, SYMBOL_BID)) / 2.0;
      double currentCandleSpeed = MathAbs(currentPrice - open);
      
      double lastCompletedSpeed = CalculateSpeed(1);
      double speed = currentCandleSpeed;
      
      if (currentCandleSpeed < lastCompletedSpeed * 0.1) {
         speed = currentCandleSpeed;
      }
      
      static datetime lastDebugTime = 0;
      datetime currentTime = TimeCurrent();
      if (currentTime - lastDebugTime > 60) {
         Print("DEBUG Speed calculation (using current candle):");
         Print("  Current candle open: ", open, ", Current mid price: ", currentPrice);
         Print("  Current candle speed: ", currentCandleSpeed);
         Print("  Last completed candle speed: ", lastCompletedSpeed);
         Print("  Selected speed: ", speed);
         lastDebugTime = currentTime;
      }
      
      return speed;
   }
}
//+------------------------------------------------------------------+
double AverageSpeed() {
   double sum = 0.0;
   int validBars = 0;
   
   for (int i = 1; i <= SpeedPeriod; i++) {
      double speed = CalculateSpeed(i);
      if (speed > 0) {
         sum += speed;
         validBars++;
      }
   }
   
   return (validBars > 0) ? sum / validBars : 0.0;
}
//+------------------------------------------------------------------+
double MaxSpeed() {
   double max = 0.0;
   for (int i = 1; i <= SpeedPeriod; i++) {
      double s = CalculateSpeed(i);
      if (s > max) max = s;
   }
   return max;
}
//+------------------------------------------------------------------+
bool CancelOrder(ulong ticket) {
   if (ticket <= 0) return true;
   
   if (!OrderSelect(ticket)) {
      return true; // Order doesn't exist, consider it cancelled
   }
   
   MqlTradeRequest request;
   MqlTradeResult result;
   ZeroMemory(request);
   ZeroMemory(result);
   
   request.action = TRADE_ACTION_REMOVE;
   request.order = ticket;
   
   bool success = OrderSend(request, result);
   if (!success || result.retcode != TRADE_RETCODE_DONE) {
      Print("Error cancelling order ", ticket, ": ", result.comment, " (", result.retcode, ")");
      return false;
   }
   
   Print("Order ", ticket, " cancelled successfully");
   return true;
}
//+------------------------------------------------------------------+
void CancelOrders() {
   if (CancelOrder(buyStopTicket)) {
      buyStopTicket = 0;
   }
   if (CancelOrder(sellStopTicket)) {
      sellStopTicket = 0;
   }
}
//+------------------------------------------------------------------+
int CountOpenPositions() {
   int count = 0;
   for (int i = 0; i < PositionsTotal(); i++) {
      if (PositionGetSymbol(i) == InpSymbol) {
         count++;
      }
   }
   return count;
}
//+------------------------------------------------------------------+
bool HasPendingOrders() {
   return (buyStopTicket > 0 && OrderSelect(buyStopTicket)) || 
          (sellStopTicket > 0 && OrderSelect(sellStopTicket));
}
//+------------------------------------------------------------------+
ulong PlacePendingOrder(ENUM_ORDER_TYPE orderType, double price, double sl, double tp) {
   MqlTradeRequest request;
   MqlTradeResult result;
   ZeroMemory(request);
   ZeroMemory(result);

   request.action = TRADE_ACTION_PENDING;
   request.symbol = InpSymbol;
   request.type = orderType;
   request.volume = LotSize;
   request.price = NormalizeDouble(price, _Digits);
   request.sl = NormalizeDouble(sl, _Digits);
   request.tp = NormalizeDouble(tp, _Digits);
   request.type_filling = ORDER_FILLING_IOC;
   request.deviation = 5;
   
   bool success = OrderSend(request, result);
   if (!success || result.retcode != TRADE_RETCODE_DONE) {
      Print("Error placing ", EnumToString(orderType), " order: ", result.comment, " (", result.retcode, ")");
      return 0;
   }
   
   Print("Successfully placed ", EnumToString(orderType), " order at ", price, " (ticket: ", result.order, ")");
   return result.order;
}
//+------------------------------------------------------------------+
bool ModifyOrder(ulong ticket, double newPrice, double newSL, double newTP) {
   if (ticket <= 0 || !OrderSelect(ticket)) return false;
   
   double currentPrice = OrderGetDouble(ORDER_PRICE_OPEN);
   double currentSL = OrderGetDouble(ORDER_SL);
   double currentTP = OrderGetDouble(ORDER_TP);
   
   // Check if modification is actually needed
   if (MathAbs(currentPrice - newPrice) < _Point && 
       MathAbs(currentSL - newSL) < _Point && 
       MathAbs(currentTP - newTP) < _Point) {
      return true; // No change needed
   }
   
   MqlTradeRequest request;
   MqlTradeResult result;
   ZeroMemory(request);
   ZeroMemory(result);
   
   request.action = TRADE_ACTION_MODIFY;
   request.order = ticket;
   request.price = NormalizeDouble(newPrice, _Digits);
   request.sl = NormalizeDouble(newSL, _Digits);
   request.tp = NormalizeDouble(newTP, _Digits);
   
   bool success = OrderSend(request, result);
   if (!success || result.retcode != TRADE_RETCODE_DONE) {
      Print("Error modifying order ", ticket, ": ", result.comment, " (", result.retcode, ")");
      return false;
   }
   
   Print("Order ", ticket, " modified successfully. New price: ", newPrice);
   return true;
}
//+------------------------------------------------------------------+
void PlaceOrUpdateOrders(double ask, double bid) {
   double speedNow = CalculateCurrentSpeed();
   double avgSpeed = AverageSpeed();
   double threshold = avgSpeed * SpeedMultiplier;
   
   // FIXED: Only proceed if speed threshold is met OR we don't have any orders yet
   bool speedTriggered = (speedNow >= threshold);
   bool hasOrders = (buyStopTicket > 0 || sellStopTicket > 0);
   
   if (!speedTriggered && hasOrders) {
      // Speed not high enough and we already have orders - don't modify them
      static datetime lastNoSpeedMessage = 0;
      datetime now = TimeCurrent();
      if (now - lastNoSpeedMessage > 300) { // Message every 5 minutes
         Print("Speed below threshold (", speedNow, " < ", threshold, "). Keeping existing orders unchanged.");
         lastNoSpeedMessage = now;
      }
      return;
   }
   
   // Check if we already have maximum positions
   if (CountOpenPositions() >= MaxPositions) {
      Print("Maximum positions (", MaxPositions, ") reached. Skipping new orders.");
      return;
   }
   
   // IMPROVED: Rate limit order updates
   datetime now = TimeCurrent();
   if (EnableDynamicOrders && hasOrders && (now - lastOrderUpdate < OrderUpdateMinutes * 60)) {
      static datetime lastRateLimitMessage = 0;
      if (now - lastRateLimitMessage > 300) { // Message every 5 minutes
         int remainingMinutes = (int)((OrderUpdateMinutes * 60 - (now - lastOrderUpdate)) / 60) + 1;
         Print("Order update rate limited. Next update allowed in ", remainingMinutes, " minutes.");
         lastRateLimitMessage = now;
      }
      return;
   }

   // Calculate new order prices
   double buyPrice = NormalizeDouble(ask + OrderDistancePoints * _Point, _Digits);
   double sellPrice = NormalizeDouble(bid - OrderDistancePoints * _Point, _Digits);
   double buySL = NormalizeDouble(buyPrice - SL_Points * _Point, _Digits);
   double buyTP = NormalizeDouble(buyPrice + TP_Points * _Point, _Digits);
   double sellSL = NormalizeDouble(sellPrice + SL_Points * _Point, _Digits);
   double sellTP = NormalizeDouble(sellPrice - TP_Points * _Point, _Digits);

   bool ordersModified = false;

   // Handle BUY STOP order
   if (buyStopTicket > 0 && OrderSelect(buyStopTicket)) {
      if (EnableDynamicOrders && speedTriggered) {
         if (ModifyOrder(buyStopTicket, buyPrice, buySL, buyTP)) {
            ordersModified = true;
         } else {
            // If modification fails, cancel and recreate
            CancelOrder(buyStopTicket);
            buyStopTicket = 0;
         }
      }
   }
   
   if (buyStopTicket == 0 && speedTriggered) {
      buyStopTicket = PlacePendingOrder(ORDER_TYPE_BUY_STOP, buyPrice, buySL, buyTP);
      if (buyStopTicket > 0) ordersModified = true;
   }

   // Handle SELL STOP order
   if (sellStopTicket > 0 && OrderSelect(sellStopTicket)) {
      if (EnableDynamicOrders && speedTriggered) {
         if (ModifyOrder(sellStopTicket, sellPrice, sellSL, sellTP)) {
            ordersModified = true;
         } else {
            // If modification fails, cancel and recreate
            CancelOrder(sellStopTicket);
            sellStopTicket = 0;
         }
      }
   }
   
   if (sellStopTicket == 0 && speedTriggered) {
      sellStopTicket = PlacePendingOrder(ORDER_TYPE_SELL_STOP, sellPrice, sellSL, sellTP);
      if (sellStopTicket > 0) ordersModified = true;
   }
   
   // Update last order update time if any orders were modified/created
   if (ordersModified) {
      lastOrderUpdate = now;
      Print("Orders updated due to speed trigger: ", speedNow, " >= ", threshold);
   }
}
//+------------------------------------------------------------------+
bool IsTradingTime() {
   datetime now = TimeCurrent();
   MqlDateTime dt;
   TimeToStruct(now, dt);
   int hour = dt.hour;
   
   // Check if market is open
   if (!SymbolInfoInteger(InpSymbol, SYMBOL_TRADE_MODE)) {
      return false; // Trading is disabled for this symbol
   }
   
   // Check market session
   datetime sessionStart, sessionEnd;
   if (!SymbolInfoSessionTrade(InpSymbol, (ENUM_DAY_OF_WEEK)dt.day_of_week, 0, sessionStart, sessionEnd)) {
      return false; // Cannot get session info
   }
   
   // Simple time check (can be enhanced for more precise session checking)
   bool withinHours = (hour >= TradingStartHour && hour < TradingEndHour);
   
   return withinHours;
}
//+------------------------------------------------------------------+
void CheckAndCleanupExecutedOrders() {
   // Check if buy stop order was executed or cancelled
   if (buyStopTicket > 0 && !OrderSelect(buyStopTicket)) {
      Print("Buy stop order ", buyStopTicket, " no longer exists (executed or cancelled)");
      buyStopTicket = 0;
      lastOrderUpdate = 0; // Reset rate limit when order is executed
   }
   
   // Check if sell stop order was executed or cancelled
   if (sellStopTicket > 0 && !OrderSelect(sellStopTicket)) {
      Print("Sell stop order ", sellStopTicket, " no longer exists (executed or cancelled)");
      sellStopTicket = 0;
      lastOrderUpdate = 0; // Reset rate limit when order is executed
   }
}
//+------------------------------------------------------------------+
void OnTimer() {
   datetime now = TimeCurrent();
   datetime nowLocal = TimeLocal();
   
   // Calculate startup period based on local time (more reliable when markets are closed)
   bool isStartupPeriod = (nowLocal - botStartTimeLocal < StartupMonitorMinutes * 60);
   
   // Check if we're in trading hours
   if (!IsTradingTime()) {
      static datetime lastMarketMessage = 0;
      if (nowLocal - lastMarketMessage > 3600) { // Message every hour when market is closed
         Print("Market is closed or outside trading hours. ", isStartupPeriod ? "Monitoring only." : "Waiting...");
         Print("Local time: ", TimeToString(nowLocal, TIME_MINUTES), " | Server time: ", TimeToString(now, TIME_MINUTES));
         lastMarketMessage = nowLocal;
      }
      CancelOrders(); // Outside trading window
      return;
   }
   
   // Clean up executed or cancelled orders
   CheckAndCleanupExecutedOrders();
   
   // Get current prices
   double ask = SymbolInfoDouble(InpSymbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(InpSymbol, SYMBOL_BID);
   
   if (ask <= 0 || bid <= 0) {
      Print("Invalid price data: Ask=", ask, ", Bid=", bid);
      return;
   }
   
   // Calculate current speed metrics (always monitor)
   double speedNow = CalculateCurrentSpeed();
   double avgSpeed = AverageSpeed();
   double maxSpeed = MaxSpeed();
   double threshold = avgSpeed * SpeedMultiplier;
   
   // Log speed information periodically
   static int logCounter = 0;
   if (++logCounter >= 10) { // Log every 10 timer calls
      if (isStartupPeriod) {
         int remainingMinutes = (int)((StartupMonitorMinutes * 60 - (nowLocal - botStartTimeLocal)) / 60);
         Print("MONITORING PHASE (", remainingMinutes, " min remaining) - Speed metrics:");
      } else {
         Print("TRADING PHASE - Speed metrics:");
      }
      Print("  Current: ", speedNow, ", Average: ", avgSpeed, ", Max: ", maxSpeed, ", Threshold: ", threshold);
      Print("  Active positions: ", CountOpenPositions(), ", Pending orders: ", (buyStopTicket > 0 ? 1 : 0) + (sellStopTicket > 0 ? 1 : 0));
      
      if (speedNow >= threshold) {
         if (isStartupPeriod) {
            Print("  SPEED TRIGGER detected but in monitoring phase - no trading yet");
         } else {
            Print("  SPEED TRIGGER: Current speed (", speedNow, ") >= Threshold (", threshold, ")");
         }
      } else {
         Print("  Waiting for speed trigger. Need: ", threshold, ", Current: ", speedNow);
      }
      
      // Show next order update time if rate limited
      if (EnableDynamicOrders && lastOrderUpdate > 0) {
         int nextUpdateMinutes = (int)((OrderUpdateMinutes * 60 - (now - lastOrderUpdate)) / 60) + 1;
         if (nextUpdateMinutes > 0) {
            Print("  Next order update allowed in: ", nextUpdateMinutes, " minutes");
         }
      }
      
      logCounter = 0;
   }
   
   // Only place orders if startup period is over
   if (!isStartupPeriod) {
      PlaceOrUpdateOrders(ask, bid);
   } else {
      // During startup, just monitor but provide occasional feedback
      static datetime lastStartupMessage = 0;
      if (nowLocal - lastStartupMessage > 300) { // Message every 5 minutes during startup
         int remainingMinutes = (int)((StartupMonitorMinutes * 60 - (nowLocal - botStartTimeLocal)) / 60);
         Print("Monitoring market conditions. Trading begins in ", remainingMinutes, " minutes... (Local: ", TimeToString(nowLocal, TIME_MINUTES), ")");
         Print("Current speed data: Current=", speedNow, ", Average=", avgSpeed, ", Threshold=", threshold);
         lastStartupMessage = nowLocal;
      }
   }
}
//+------------------------------------------------------------------+
void OnTick() {
   // Keep OnTick for immediate response to critical events
   // but main logic is now in OnTimer()
   
   // Clean up executed orders immediately
   CheckAndCleanupExecutedOrders();
}
//+------------------------------------------------------------------+