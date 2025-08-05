//+------------------------------------------------------------------+
void CheckOrderIntegrity() {
    // Count our existing orders
    int buyStopCount = 0;
    int sellStopCount = 0;
    ulong foundBuyTicket = 0;
    ulong foundSellTicket = 0;
    
    for (int i = 0; i < OrdersTotal(); i++) {
        if (OrderGetTicket(i) > 0) {
            string orderSymbol = OrderGetString(ORDER_SYMBOL);
            ulong orderMagic = OrderGetInteger(ORDER_MAGIC);
            ENUM_ORDER_TYPE orderType = (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
            ulong ticket = OrderGetTicket(i);
            
            if (orderSymbol == currentSymbol && orderMagic == MagicNumber) {
                if (orderType == ORDER_TYPE_BUY_STOP) {
                    buyStopCount++;
                    if (buyStopCount == 1) foundBuyTicket = ticket;
                } else if (orderType == ORDER_TYPE_SELL_STOP) {
                    sellStopCount++;
                    if (sellStopCount == 1) foundSellTicket = ticket;
                }
            }
        }
    }
    
    // If we have more than one of each type, delete extras
    if (buyStopCount > 1) {
        Print("WARNING: Found ", buyStopCount, " BUY STOP orders, cleaning up extras...");
        for (int i = OrdersTotal() - 1; i >= 0; i--) {
            if (OrderGetTicket(i) > 0) {
                string orderSymbol = OrderGetString(ORDER_SYMBOL);
                ulong orderMagic = OrderGetInteger(ORDER_MAGIC);
                ENUM_ORDER_TYPE orderType = (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
                ulong ticket = OrderGetTicket(i);
                
                if (orderSymbol == currentSymbol && orderMagic == MagicNumber && 
                    orderType == ORDER_TYPE_BUY_STOP && ticket != foundBuyTicket) {
                    DeleteOrder(ticket);
                    Print("Deleted extra BUY STOP order: ", ticket);
                }
            }
        }
    }
    
    if (sellStopCount > 1) {
        Print("WARNING: Found ", sellStopCount, " SELL STOP orders, cleaning up extras...");
        for (int i = OrdersTotal() - 1; i >= 0; i--) {
            if (OrderGetTicket(i) > 0) {
                string orderSymbol = OrderGetString(ORDER_SYMBOL);
                ulong orderMagic = OrderGetInteger(ORDER_MAGIC);
                ENUM_ORDER_TYPE orderType = (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
                ulong ticket = OrderGetTicket(i);
                
                if (orderSymbol == currentSymbol && orderMagic == MagicNumber && 
                    orderType == ORDER_TYPE_SELL_STOP && ticket != foundSellTicket) {
                    DeleteOrder(ticket);
                    Print("Deleted extra SELL STOP order: ", ticket);
                }
            }
        }
    }
    
    // Update our ticket variables with the found orders
    if (buyStopCount == 1 && buyStopTicket != foundBuyTicket) {
        buyStopTicket = foundBuyTicket;
        Print("Updated BUY STOP ticket to: ", buyStopTicket);
    } else if (buyStopCount == 0) {
        buyStopTicket = 0;
    }
    
    if (sellStopCount == 1 && sellStopTicket != foundSellTicket) {
        sellStopTicket = foundSellTicket;
        Print("Updated SELL STOP ticket to: ", sellStopTicket);
    } else if (sellStopCount == 0) {
        sellStopTicket = 0;
    }
}

//+------------------------------------------------------------------+
void CleanupExistingOrders() {
    int totalOrders = OrdersTotal();
    Print("Cleaning up existing orders. Total pending orders: ", totalOrders);
    
    for (int i = totalOrders - 1; i >= 0; i--) {
        if (OrderGetTicket(i) > 0) {
            string orderSymbol = OrderGetString(ORDER_SYMBOL);
            ulong orderMagic = OrderGetInteger(ORDER_MAGIC);
            ENUM_ORDER_TYPE orderType = (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
            ulong ticket = OrderGetTicket(i);
            
            // Delete orders that match our symbol and magic number
            if (orderSymbol == currentSymbol && orderMagic == MagicNumber) {
                if (orderType == ORDER_TYPE_BUY_STOP || orderType == ORDER_TYPE_SELL_STOP) {
                    if (DeleteOrder(ticket)) {
                        Print("Deleted existing ", EnumToString(orderType), " order: ", ticket);
                    }
                }
            }
        }
    }
    
    // Reset ticket variables
    buyStopTicket = 0;
    sellStopTicket = 0;
    
    Print("Cleanup completed. Buy/Sell stop tickets reset.");
}

//+------------------------------------------------------------------+
//|                                       PercentageTrailingBot.mq5  |
//|                                       Advanced Percentage-Based  |
//|                                       Trailing Stop Expert       |
//+------------------------------------------------------------------+
#property strict

// Input Parameters
input double   OrderDeltaPercent     = 0.1;        // Price delta between stop orders (%)
input double   RiskPercent           = 1.0;        // Maximum risk per trade (% of account)
input double   TrailingPercent       = 50.0;       // Trailing percentage between open and current price (%)
input int      UpdateIntervalSeconds = 300;        // Update interval for pending orders (seconds)
input int      MagicNumber           = 123456;     // Magic number for orders
input string   TradeComment          = "PCT_Trail"; // Comment for trades

// Global variables
string currentSymbol;
ENUM_TIMEFRAMES currentTimeframe;
ulong buyStopTicket = 0;
ulong sellStopTicket = 0;
datetime lastPendingUpdate = 0;

// Broker specification cache
double symbolPoint;
int symbolDigits;
double minLot;
double maxLot;
double lotStep;
double minStopLevel;
double tickSize;
double tickValue;

//+------------------------------------------------------------------+
int OnInit() {
    // Get current symbol and timeframe from chart
    currentSymbol = Symbol();
    currentTimeframe = Period();
    
    // Cache broker specifications
    if (!CacheBrokerSpecs()) {
        Print("Error: Failed to get broker specifications");
        return INIT_FAILED;
    }
    
    PrintBrokerSpecs();
    
    // Clean up any existing orders with our magic number
    CleanupExistingOrders();
    
    Print("PercentageTrailingBot initialized successfully");
    Print("Symbol: ", currentSymbol, ", Timeframe: ", EnumToString(currentTimeframe));
    Print("Order delta: ", OrderDeltaPercent, "%, Risk: ", RiskPercent, "%, Trailing: ", TrailingPercent, "%");
    Print("Update interval: ", UpdateIntervalSeconds, " seconds");
    
    return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason) {
    Print("PercentageTrailingBot deinitialized. Reason: ", reason);
}

//+------------------------------------------------------------------+
bool CacheBrokerSpecs() {
    symbolPoint = SymbolInfoDouble(currentSymbol, SYMBOL_POINT);
    symbolDigits = (int)SymbolInfoInteger(currentSymbol, SYMBOL_DIGITS);
    minLot = SymbolInfoDouble(currentSymbol, SYMBOL_VOLUME_MIN);
    maxLot = SymbolInfoDouble(currentSymbol, SYMBOL_VOLUME_MAX);
    lotStep = SymbolInfoDouble(currentSymbol, SYMBOL_VOLUME_STEP);
    minStopLevel = SymbolInfoInteger(currentSymbol, SYMBOL_TRADE_STOPS_LEVEL) * symbolPoint;
    tickSize = SymbolInfoDouble(currentSymbol, SYMBOL_TRADE_TICK_SIZE);
    tickValue = SymbolInfoDouble(currentSymbol, SYMBOL_TRADE_TICK_VALUE);
    
    if (symbolPoint <= 0 || tickValue <= 0) {
        return false;
    }
    
    return true;
}

//+------------------------------------------------------------------+
void PrintBrokerSpecs() {
    Print("=== Broker Specifications ===");
    Print("Point: ", symbolPoint, ", Digits: ", symbolDigits);
    Print("Min Lot: ", minLot, ", Max Lot: ", maxLot, ", Lot Step: ", lotStep);
    Print("Min Stop Level: ", minStopLevel, " (", (minStopLevel / symbolPoint), " points)");
    Print("Tick Size: ", tickSize, ", Tick Value: ", tickValue);
}

//+------------------------------------------------------------------+
double NormalizePrice(double price) {
    return NormalizeDouble(price, symbolDigits);
}

//+------------------------------------------------------------------+
double CalculatePercentageDistance(double price, double percent) {
    double distance = price * percent / 100.0;
    // Normalize to tick size
    distance = MathRound(distance / tickSize) * tickSize;
    return NormalizePrice(distance);
}

//+------------------------------------------------------------------+
double CalculateLotSize(double openPrice, double stopLoss) {
    if (tickValue <= 0) return minLot;
    
    double accountBalance = AccountInfoDouble(ACCOUNT_BALANCE);
    double maxRiskAmount = accountBalance * RiskPercent / 100.0;
    double stopDistance = MathAbs(openPrice - stopLoss);
    
    if (stopDistance <= 0) return minLot;
    
    double pointValue = tickValue * (symbolPoint / tickSize);
    double lotSize = maxRiskAmount / (stopDistance / symbolPoint * pointValue);
    
    // Normalize to lot step
    lotSize = MathFloor(lotSize / lotStep) * lotStep;
    
    // Apply limits
    if (lotSize < minLot) lotSize = minLot;
    if (lotSize > maxLot) lotSize = maxLot;
    
    return NormalizeDouble(lotSize, 2);
}

//+------------------------------------------------------------------+
bool HasMarketPositions() {
    for (int i = 0; i < PositionsTotal(); i++) {
        if (PositionGetSymbol(i) == currentSymbol) {
            ulong magic = PositionGetInteger(POSITION_MAGIC);
            if (magic == MagicNumber || magic == 0) { // Include positions without magic number
                return true;
            }
        }
    }
    return false;
}

//+------------------------------------------------------------------+
void DeletePendingOrders() {
    bool ordersDeleted = false;
    
    if (buyStopTicket > 0) {
        if (DeleteOrder(buyStopTicket)) {
            Print("Deleted BUY STOP order: ", buyStopTicket);
            buyStopTicket = 0;
            ordersDeleted = true;
        }
    }
    
    if (sellStopTicket > 0) {
        if (DeleteOrder(sellStopTicket)) {
            Print("Deleted SELL STOP order: ", sellStopTicket);
            sellStopTicket = 0;
            ordersDeleted = true;
        }
    }
    
    if (ordersDeleted) {
        Print("Switched from pending orders to position trailing mode");
    }
}

//+------------------------------------------------------------------+
bool DeleteOrder(ulong ticket) {
    if (ticket <= 0) return true;
    
    if (!OrderSelect(ticket)) {
        return true; // Order doesn't exist
    }
    
    MqlTradeRequest request;
    MqlTradeResult result;
    ZeroMemory(request);
    ZeroMemory(result);
    
    request.action = TRADE_ACTION_REMOVE;
    request.order = ticket;
    
    bool success = OrderSend(request, result);
    if (!success || result.retcode != TRADE_RETCODE_DONE) {
        Print("Error deleting order ", ticket, ": ", result.comment, " (", result.retcode, ")");
        return false;
    }
    
    return true;
}

//+------------------------------------------------------------------+
void TrailMarketPositions() {
    double ask = SymbolInfoDouble(currentSymbol, SYMBOL_ASK);
    double bid = SymbolInfoDouble(currentSymbol, SYMBOL_BID);
    
    for (int i = 0; i < PositionsTotal(); i++) {
        if (PositionGetSymbol(i) == currentSymbol) {
            ulong magic = PositionGetInteger(POSITION_MAGIC);
            if (magic == MagicNumber || magic == 0) { // Include positions without magic number
                ulong ticket = PositionGetTicket(i);
                ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
                double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
                double currentSL = PositionGetDouble(POSITION_SL);
                double currentTP = PositionGetDouble(POSITION_TP);
                
                TrailPosition(ticket, posType, openPrice, currentSL, currentTP, ask, bid);
            }
        }
    }
}

//+------------------------------------------------------------------+
void TrailPosition(ulong ticket, ENUM_POSITION_TYPE posType, double openPrice, 
                   double currentSL, double currentTP, double ask, double bid) {
    
    double currentPrice = (posType == POSITION_TYPE_BUY) ? bid : ask;
    double newSL = 0;
    bool shouldUpdateSL = false;
    bool shouldDeleteTP = false;
    
    // Calculate trailing percentage (default 50%)
    double trailingFactor = TrailingPercent / 100.0;
    
    if (posType == POSITION_TYPE_BUY) {
        // BUY position: trail SL up when in profit
        if (currentPrice > openPrice) {
            // Calculate percentage between open price and current price
            double profitDistance = currentPrice - openPrice;
            double idealSL = openPrice + profitDistance * trailingFactor;
            
            // Ensure minimum distance from current price
            double minSLLevel = currentPrice - minStopLevel;
            newSL = (idealSL > minSLLevel) ? minSLLevel : idealSL;
            
            // Normalize to tick size and symbol digits
            newSL = MathRound(newSL / tickSize) * tickSize;
            newSL = NormalizePrice(newSL);
            
            // Only move SL up and only if it's better than current SL
            if (newSL > openPrice && (currentSL == 0 || newSL > currentSL)) {
                shouldUpdateSL = true;
                shouldDeleteTP = true;
                
                // Detailed logging
                Print("BUY trailing calculation - Open: ", openPrice, ", Current: ", currentPrice, 
                      ", Ideal SL: ", idealSL, ", Final SL: ", newSL, ", Current SL: ", currentSL);
                Print("Profit distance: ", profitDistance, ", Min SL level: ", minSLLevel, 
                      ", Trailing factor: ", trailingFactor);
            }
        }
    } else { // SELL position
        // SELL position: trail SL down when in profit
        if (currentPrice < openPrice) {
            // Calculate percentage between open price and current price
            double profitDistance = openPrice - currentPrice;
            double idealSL = openPrice - profitDistance * trailingFactor;
            
            // Ensure minimum distance from current price
            double maxSLLevel = currentPrice + minStopLevel;
            newSL = (idealSL < maxSLLevel) ? maxSLLevel : idealSL;
            
            // Normalize to tick size and symbol digits
            newSL = MathRound(newSL / tickSize) * tickSize;
            newSL = NormalizePrice(newSL);
            
            // Only move SL down and only if it's better than current SL
            if (newSL < openPrice && (currentSL == 0 || newSL < currentSL)) {
                shouldUpdateSL = true;
                shouldDeleteTP = true;
                
                // Detailed logging
                Print("SELL trailing calculation - Open: ", openPrice, ", Current: ", currentPrice, 
                      ", Ideal SL: ", idealSL, ", Final SL: ", newSL, ", Current SL: ", currentSL);
                Print("Profit distance: ", profitDistance, ", Max SL level: ", maxSLLevel, 
                      ", Trailing factor: ", trailingFactor);
            }
        }
    }
    
    if (shouldUpdateSL) {
        if (ModifyPosition(ticket, newSL, shouldDeleteTP ? 0 : currentTP)) {
            Print("Position ", ticket, " (", EnumToString(posType), ") - SL trailed to: ", newSL);
            if (shouldDeleteTP && currentTP != 0) {
                Print("TP deleted for position ", ticket);
            }
        }
    }
}

//+------------------------------------------------------------------+
bool ModifyPosition(ulong ticket, double newSL, double newTP) {
    if (!PositionSelectByTicket(ticket)) {
        Print("Error: Position ", ticket, " not found");
        return false;
    }
    
    double currentSL = PositionGetDouble(POSITION_SL);
    double currentTP = PositionGetDouble(POSITION_TP);
    
    // Check if modification is needed
    if (MathAbs(currentSL - newSL) < symbolPoint && MathAbs(currentTP - newTP) < symbolPoint) {
        return true; // No change needed
    }
    
    MqlTradeRequest request;
    MqlTradeResult result;
    ZeroMemory(request);
    ZeroMemory(result);
    
    request.action = TRADE_ACTION_SLTP;
    request.symbol = currentSymbol;
    request.position = ticket;
    request.sl = newSL;
    request.tp = newTP;
    request.magic = MagicNumber;
    
    bool success = OrderSend(request, result);
    if (!success || result.retcode != TRADE_RETCODE_DONE) {
        Print("Error modifying position ", ticket, ": ", result.comment, " (", result.retcode, ")");
        return false;
    }
    
    return true;
}

//+------------------------------------------------------------------+
void ManagePendingOrders() {
    datetime now = TimeCurrent();
    
    // Check if it's time to update pending orders
    if (now - lastPendingUpdate < UpdateIntervalSeconds) {
        return;
    }
    
    // Ensure order integrity (no more than 1 BUY STOP and 1 SELL STOP)
    CheckOrderIntegrity();
    
    double ask = SymbolInfoDouble(currentSymbol, SYMBOL_ASK);
    double bid = SymbolInfoDouble(currentSymbol, SYMBOL_BID);
    double midPrice = (ask + bid) / 2.0;
    
    // Calculate delta distance (0.1% of current price)
    double deltaDistance = CalculatePercentageDistance(midPrice, OrderDeltaPercent);
    
    // Ensure minimum distance from current price
    double minDistance = minStopLevel;
    if (deltaDistance < minDistance) {
        deltaDistance = minDistance;
    }
    
    // Calculate order prices
    double buyStopPrice = NormalizePrice(midPrice + deltaDistance / 2.0);
    double sellStopPrice = NormalizePrice(midPrice - deltaDistance / 2.0);
    
    // Calculate SL and TP distances (0.1% each)
    double slDistance = CalculatePercentageDistance(midPrice, OrderDeltaPercent);
    double tpDistance = CalculatePercentageDistance(midPrice, OrderDeltaPercent);
    
    // Ensure minimum SL distance
    if (slDistance < minStopLevel) {
        slDistance = minStopLevel;
    }
    if (tpDistance < minStopLevel) {
        tpDistance = minStopLevel;
    }
    
    // Calculate SL and TP for each order
    double buySL = NormalizePrice(buyStopPrice - slDistance);
    double buyTP = NormalizePrice(buyStopPrice + tpDistance);
    double sellSL = NormalizePrice(sellStopPrice + slDistance);
    double sellTP = NormalizePrice(sellStopPrice - tpDistance);
    
    // Calculate lot sizes
    double buyLotSize = CalculateLotSize(buyStopPrice, buySL);
    double sellLotSize = CalculateLotSize(sellStopPrice, sellSL);
    
    // Manage BUY STOP order
    ManageBuyStopOrder(buyStopPrice, buySL, buyTP, buyLotSize);
    
    // Manage SELL STOP order
    ManageSellStopOrder(sellStopPrice, sellSL, sellTP, sellLotSize);
    
    lastPendingUpdate = now;
    
    static datetime lastLogTime = 0;
    if (now - lastLogTime > 60) { // Log every minute
        Print("Pending orders updated - BUY STOP: ", buyStopPrice, ", SELL STOP: ", sellStopPrice);
        Print("Delta distance: ", deltaDistance, " (", (deltaDistance/symbolPoint), " points)");
        Print("Lot sizes - BUY: ", buyLotSize, ", SELL: ", sellLotSize);
        lastLogTime = now;
    }
}

//+------------------------------------------------------------------+
void ManageBuyStopOrder(double price, double sl, double tp, double lotSize) {
    bool needsRecreate = false;
    
    if (buyStopTicket > 0 && OrderSelect(buyStopTicket)) {
        // Check if current order needs modification
        double currentPrice = OrderGetDouble(ORDER_PRICE_OPEN);
        double currentSL = OrderGetDouble(ORDER_SL);
        double currentTP = OrderGetDouble(ORDER_TP);
        double currentLot = OrderGetDouble(ORDER_VOLUME_CURRENT);
        
        // Check if lot size changed significantly
        if (MathAbs(currentLot - lotSize) > lotStep / 2.0) {
            needsRecreate = true;
        }
        // Check if price changed significantly
        else if (MathAbs(currentPrice - price) > symbolPoint) {
            if (ModifyOrder(buyStopTicket, price, sl, tp)) {
                return; // Successfully modified
            } else {
                needsRecreate = true;
            }
        }
        // Check if SL/TP needs update
        else if (MathAbs(currentSL - sl) > symbolPoint || MathAbs(currentTP - tp) > symbolPoint) {
            ModifyOrder(buyStopTicket, currentPrice, sl, tp);
            return;
        } else {
            return; // No changes needed
        }
    } else {
        needsRecreate = true;
    }
    
    if (needsRecreate) {
        // Delete existing order if it exists
        if (buyStopTicket > 0) {
            DeleteOrder(buyStopTicket);
        }
        
        // Create new order
        buyStopTicket = PlacePendingOrder(ORDER_TYPE_BUY_STOP, price, sl, tp, lotSize);
    }
}

//+------------------------------------------------------------------+
void ManageSellStopOrder(double price, double sl, double tp, double lotSize) {
    bool needsRecreate = false;
    
    if (sellStopTicket > 0 && OrderSelect(sellStopTicket)) {
        // Check if current order needs modification
        double currentPrice = OrderGetDouble(ORDER_PRICE_OPEN);
        double currentSL = OrderGetDouble(ORDER_SL);
        double currentTP = OrderGetDouble(ORDER_TP);
        double currentLot = OrderGetDouble(ORDER_VOLUME_CURRENT);
        
        // Check if lot size changed significantly
        if (MathAbs(currentLot - lotSize) > lotStep / 2.0) {
            needsRecreate = true;
        }
        // Check if price changed significantly
        else if (MathAbs(currentPrice - price) > symbolPoint) {
            if (ModifyOrder(sellStopTicket, price, sl, tp)) {
                return; // Successfully modified
            } else {
                needsRecreate = true;
            }
        }
        // Check if SL/TP needs update
        else if (MathAbs(currentSL - sl) > symbolPoint || MathAbs(currentTP - tp) > symbolPoint) {
            ModifyOrder(sellStopTicket, currentPrice, sl, tp);
            return;
        } else {
            return; // No changes needed
        }
    } else {
        needsRecreate = true;
    }
    
    if (needsRecreate) {
        // Delete existing order if it exists
        if (sellStopTicket > 0) {
            DeleteOrder(sellStopTicket);
        }
        
        // Create new order
        sellStopTicket = PlacePendingOrder(ORDER_TYPE_SELL_STOP, price, sl, tp, lotSize);
    }
}

//+------------------------------------------------------------------+
ulong PlacePendingOrder(ENUM_ORDER_TYPE orderType, double price, double sl, double tp, double lotSize) {
    MqlTradeRequest request;
    MqlTradeResult result;
    ZeroMemory(request);
    ZeroMemory(result);
    
    request.action = TRADE_ACTION_PENDING;
    request.symbol = currentSymbol;
    request.type = orderType;
    request.volume = lotSize;
    request.price = price;
    request.sl = sl;
    request.tp = tp;
    request.magic = MagicNumber;
    request.comment = TradeComment;
    request.type_filling = ORDER_FILLING_IOC;
    request.deviation = 10;
    
    bool success = OrderSend(request, result);
    if (!success || result.retcode != TRADE_RETCODE_DONE) {
        Print("Error placing ", EnumToString(orderType), " order: ", result.comment, " (", result.retcode, ")");
        Print("Price: ", price, ", SL: ", sl, ", TP: ", tp, ", Lot: ", lotSize);
        return 0;
    }
    
    Print("Successfully placed ", EnumToString(orderType), " order at ", price, " (ticket: ", result.order, ")");
    return result.order;
}

//+------------------------------------------------------------------+
bool ModifyOrder(ulong ticket, double newPrice, double newSL, double newTP) {
    if (ticket <= 0 || !OrderSelect(ticket)) return false;
    
    MqlTradeRequest request;
    MqlTradeResult result;
    ZeroMemory(request);
    ZeroMemory(result);
    
    request.action = TRADE_ACTION_MODIFY;
    request.order = ticket;
    request.price = newPrice;
    request.sl = newSL;
    request.tp = newTP;
    
    bool success = OrderSend(request, result);
    if (!success || result.retcode != TRADE_RETCODE_DONE) {
        Print("Error modifying order ", ticket, ": ", result.comment, " (", result.retcode, ")");
        return false;
    }
    
    return true;
}

//+------------------------------------------------------------------+
void CleanupExecutedOrders() {
    // Check if buy stop order was executed or cancelled
    if (buyStopTicket > 0 && !OrderSelect(buyStopTicket)) {
        Print("BUY STOP order ", buyStopTicket, " no longer exists (executed or cancelled)");
        buyStopTicket = 0;
    }
    
    // Check if sell stop order was executed or cancelled
    if (sellStopTicket > 0 && !OrderSelect(sellStopTicket)) {
        Print("SELL STOP order ", sellStopTicket, " no longer exists (executed or cancelled)");
        sellStopTicket = 0;
    }
}

//+------------------------------------------------------------------+
void OnTick() {
    // Clean up executed orders
    CleanupExecutedOrders();
    
    // Check if we have market positions
    if (HasMarketPositions()) {
        // Delete pending orders and trail market positions
        DeletePendingOrders();
        TrailMarketPositions();
    } else {
        // Manage pending orders
        ManagePendingOrders();
    }
}
//+------------------------------------------------------------------+