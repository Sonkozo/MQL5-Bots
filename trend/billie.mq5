#include <Trade\Trade.mqh>
#include <Indicators\Trend.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\OrderInfo.mqh>

//--- Input parameters

//--- Global variables
CTrade        Trade;
CPositionInfo PositionInfo;
COrderInfo    OrderInfo;
int           BrokerOrderLimit;
int           CurrentThreshold;
datetime      LastActionTime;


input double LotSize = 5;          // Lot size
input int FastMAPeriod = 13;         // Fast MA period
input int SlowMAPeriod = 26;         // Slow MA period
input double PendingOrderDistance = 0.05; // 0.05% distance for pending orders
input double TakeProfitPercent = 0.2; // 99% take profit
input double StopLossPercent = 0.2;  // 99% stop loss
input int Slippage = 3;              // Slippage in points
input int MagicNumber = 123456;      // Magic number for order identification

int FastMA;
int SlowMA;
int FastMAHandle;
int SlowMAHandle;
ulong PendingOrderTicket = 0;
ENUM_TIMEFRAMES Timeframe = PERIOD_M1; // 1-minute timeframe

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   // Initialize MA indicators for 1-minute timeframe
   FastMAHandle = iMA(_Symbol, Timeframe, FastMAPeriod, 0, MODE_EMA, PRICE_CLOSE);
   SlowMAHandle = iMA(_Symbol, Timeframe, SlowMAPeriod, 0, MODE_EMA, PRICE_CLOSE);
   
   if(FastMAHandle == INVALID_HANDLE || SlowMAHandle == INVALID_HANDLE)
   {
      Print("Error creating MA indicators");
      return(INIT_FAILED);
   }
   
   Trade.SetExpertMagicNumber(MagicNumber);
   Trade.SetDeviationInPoints(Slippage);
   
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   // Release indicators
   if(FastMAHandle != INVALID_HANDLE) IndicatorRelease(FastMAHandle);
   if(SlowMAHandle != INVALID_HANDLE) IndicatorRelease(SlowMAHandle);
}

//+------------------------------------------------------------------+
//| Get MA value                                                     |
//+------------------------------------------------------------------+
double GetMAValue(int handle, int shift)
{
   double ma[1];
   if(CopyBuffer(handle, 0, shift, 1, ma) != 1)
   {
      Print("Error getting MA value");
      return(0);
   }
   return(ma[0]);
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   // Check for cross conditions
   CheckForCross();
   
   // Check if we need to modify or delete pending orders
   //ManagePendingOrders();
   
}

//+------------------------------------------------------------------+
//| Check for Golden/Death Cross                                     |
//+------------------------------------------------------------------+
void CheckForCross()
{
   static bool prevGoldenCross = false;
   static bool prevDeathCross = false;
   
   // Get current and previous MA values
   double fastMA0 = GetMAValue(FastMAHandle, 1);
   double fastMA1 = GetMAValue(FastMAHandle, 2);
   double slowMA0 = GetMAValue(SlowMAHandle, 1);
   double slowMA1 = GetMAValue(SlowMAHandle, 2);
   
   // Check for Golden Cross (fast MA crosses above slow MA)/
   bool goldenCross = (fastMA1 <= slowMA1) && (fastMA0 > slowMA0);
   
   // Check for Death Cross (fast MA crosses below slow MA)
   bool deathCross = (fastMA1 >= slowMA1) && (fastMA0 < slowMA0);
   
   // If new golden cross detected
   if(goldenCross && !prevGoldenCross)
   {
      PlaceBuyStopOrder();
      prevGoldenCross = true;
      prevDeathCross = false;
   }
   
   // If new death cross detected
   if(deathCross && !prevDeathCross)
   {
      PlaceSellStopOrder();
      prevDeathCross = true;
      prevGoldenCross = false;
   }
}


//+------------------------------------------------------------------+
//| Place Buy Stop Order                                             |
//+------------------------------------------------------------------+
void PlaceBuyStopOrder()
{
   // Delete any existing pending order
   if(PendingOrderTicket != 0)
   {
      Trade.OrderDelete(PendingOrderTicket);
      PendingOrderTicket = 0;
   }
   
   // Calculate order price (current price + 0.05%)
   double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double orderPrice = currentPrice * (1 + PendingOrderDistance);
   
   // Calculate TP and SL prices (99%)
   double tpPrice = orderPrice * (1 + TakeProfitPercent);
   double slPrice = orderPrice * (1 - StopLossPercent);
   
   // Place buy stop order with TP/SL
   Trade.BuyStop(LotSize, orderPrice, _Symbol, slPrice, tpPrice, ORDER_TIME_GTC, 0, "Golden Cross Buy Stop");
   Alert("Pending order executed for: "+LotSize+" at: "+orderPrice+"!");
   PendingOrderTicket = Trade.ResultOrder();
}

//+------------------------------------------------------------------+
//| Place Sell Stop Order                                            |
//+------------------------------------------------------------------+
void PlaceSellStopOrder()
{
   // Delete any existing pending order
   if(PendingOrderTicket != 0)
   {
      Trade.OrderDelete(PendingOrderTicket);
      PendingOrderTicket = 0;
   }
   
   // Calculate order price (current price - 0.05%)
   double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double orderPrice = currentPrice * (1 - PendingOrderDistance);
   
   // Calculate TP and SL prices (99%)
   double tpPrice = orderPrice * (1 - TakeProfitPercent);
   double slPrice = orderPrice * (1 + StopLossPercent);
   
   // Place sell stop order with TP/SL
   //Trade.SellStop(LotSize, orderPrice, _Symbol, slPrice, tpPrice, ORDER_TIME_GTC, 0, "Death Cross Sell Stop");
   Alert("Pending order executed for: "+LotSize+" at: "+orderPrice+"!");

   PendingOrderTicket = Trade.ResultOrder();
}

//+------------------------------------------------------------------+
//| Manage Pending Orders                                            |
//+------------------------------------------------------------------+
void ManagePendingOrders()
{
   // If we have an active pending order
   if(PendingOrderTicket != 0)
   {
      // Check if order still exists
      if(!OrderSelect(PendingOrderTicket))
      {
         PendingOrderTicket = 0;
         return;
      }
     
      // Get current MA values
      double fastMA0 = GetMAValue(FastMAHandle, 0);
      double slowMA0 = GetMAValue(SlowMAHandle, 0);
      // If the cross condition is no longer valid, delete the pending order
      if((OrderGetInteger(ORDER_TYPE) == ORDER_TYPE_BUY_STOP && fastMA0 <= slowMA0) ||
         (OrderGetInteger(ORDER_TYPE) == ORDER_TYPE_SELL_STOP && fastMA0 >= slowMA0))
      {
         //Trade.OrderDelete(PendingOrderTicket);
         PendingOrderTicket = 0;
      }
   }
}

