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
input bool     EnableDynamicOrders  = true;       // Enable dynamic order updates
input int      MaxPositions         = 1;          // Maximum open positions

// Order tickets
ulong buyStopTicket = 0;
ulong sellStopTicket = 0;

// Position tracking
datetime lastPositionCheck = 0;

//+------------------------------------------------------------------+
int OnInit() {
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
   return MathAbs(close - open);
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
   double speedNow = CalculateSpeed(0);
   double avgSpeed = AverageSpeed();
   double threshold = avgSpeed * SpeedMultiplier;

   if (speedNow < threshold) {
      if (!EnableDynamicOrders) {
         return; // Not fast enough and dynamic updates disabled
      }
   }
   
   // Check if we already have maximum positions
   if (CountOpenPositions() >= MaxPositions) {
      Print("Maximum positions (", MaxPositions, ") reached. Skipping new orders.");
      return;
   }

   // Calculate new order prices
   double buyPrice = NormalizeDouble(ask + OrderDistancePoints * _Point, _Digits);
   double sellPrice = NormalizeDouble(bid - OrderDistancePoints * _Point, _Digits);
   double buySL = NormalizeDouble(buyPrice - SL_Points * _Point, _Digits);
   double buyTP = NormalizeDouble(buyPrice + TP_Points * _Point, _Digits);
   double sellSL = NormalizeDouble(sellPrice + SL_Points * _Point, _Digits);
   double sellTP = NormalizeDouble(sellPrice - TP_Points * _Point, _Digits);

   // Handle BUY STOP order
   if (buyStopTicket > 0 && OrderSelect(buyStopTicket)) {
      if (EnableDynamicOrders) {
         if (!ModifyOrder(buyStopTicket, buyPrice, buySL, buyTP)) {
            // If modification fails, cancel and recreate
            CancelOrder(buyStopTicket);
            buyStopTicket = 0;
         }
      }
   }
   
   if (buyStopTicket == 0 && speedNow >= threshold) {
      buyStopTicket = PlacePendingOrder(ORDER_TYPE_BUY_STOP, buyPrice, buySL, buyTP);
   }

   // Handle SELL STOP order
   if (sellStopTicket > 0 && OrderSelect(sellStopTicket)) {
      if (EnableDynamicOrders) {
         if (!ModifyOrder(sellStopTicket, sellPrice, sellSL, sellTP)) {
            // If modification fails, cancel and recreate
            CancelOrder(sellStopTicket);
            sellStopTicket = 0;
         }
      }
   }
   
   if (sellStopTicket == 0 && speedNow >= threshold) {
      sellStopTicket = PlacePendingOrder(ORDER_TYPE_SELL_STOP, sellPrice, sellSL, sellTP);
   }
}
//+------------------------------------------------------------------+
bool IsTradingTime() {
   datetime now = TimeCurrent();
   MqlDateTime dt;
   TimeToStruct(now, dt);
   int hour = dt.hour;
   
   return (hour >= TradingStartHour && hour < TradingEndHour);
}
//+------------------------------------------------------------------+
void CheckAndCleanupExecutedOrders() {
   // Check if buy stop order was executed or cancelled
   if (buyStopTicket > 0 && !OrderSelect(buyStopTicket)) {
      Print("Buy stop order ", buyStopTicket, " no longer exists (executed or cancelled)");
      buyStopTicket = 0;
   }
   
   // Check if sell stop order was executed or cancelled
   if (sellStopTicket > 0 && !OrderSelect(sellStopTicket)) {
      Print("Sell stop order ", sellStopTicket, " no longer exists (executed or cancelled)");
      sellStopTicket = 0;
   }
}
//+------------------------------------------------------------------+
void OnTimer() {
   // Check if we're in trading hours
   if (!IsTradingTime()) {
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
   
   // Calculate current speed metrics
   double speedNow = CalculateSpeed(0);
   double avgSpeed = AverageSpeed();
   double maxSpeed = MaxSpeed();
   
   // Log speed information periodically
   static int logCounter = 0;
   if (++logCounter >= 10) { // Log every 10 timer calls
      Print("Speed metrics - Current: ", speedNow, ", Average: ", avgSpeed, ", Max: ", maxSpeed);
      Print("Active positions: ", CountOpenPositions(), ", Pending orders: ", (buyStopTicket > 0 ? 1 : 0) + (sellStopTicket > 0 ? 1 : 0));
      logCounter = 0;
   }
   
   // Place or update orders
   PlaceOrUpdateOrders(ask, bid);
}
//+------------------------------------------------------------------+
void OnTick() {
   // Keep OnTick for immediate response to critical events
   // but main logic is now in OnTimer()
   
   // Clean up executed orders immediately
   CheckAndCleanupExecutedOrders();
}
//+------------------------------------------------------------------+