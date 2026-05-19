//+------------------------------------------------------------------+
//|                                                Bridge_Gemini.mqh |
//|                                      AI Analyst WebRequest Bridge|
//+------------------------------------------------------------------+
#property copyright "TONO / AI Assistant"
#property strict

//====================================================================
// STRUCT UNTUK DATA GEMINI
//====================================================================
struct GeminiSetupData
{
   string   symbol;
   string   timeframe;
   double   bid_price;
   double   ask_price;
   double   buy_score;
   double   sell_score;
   double   adx_value;
   int      spread_points;
   string   zone_status;
   double   supply_top;
   double   supply_bot;
   double   demand_top;
   double   demand_bot;
   bool     ema_bull;
   bool     macd_bull;
   bool     rsi_bull;
   bool     stoch_bull;
};

//====================================================================
// KELAS BRIDGE GEMINI
//====================================================================
class CGeminiBridge
{
private:
   string m_api_url;
   
public:
   // Constructor: Masukkan URL local backend Node.js / Python Anda
   CGeminiBridge(string url = "http://127.0.0.1:5000/api/analyze-setup")
   {
      m_api_url = url;
   }
   
   // Fungsi untuk menembak data ke Server
   bool SendDataToAI(GeminiSetupData &data)
   {
      string headers = "Content-Type: application/json\r\n";
      string payload = FormatJSON(data);
      
      char postData[];
      StringToCharArray(payload, postData, 0, WHOLE_ARRAY, CP_UTF8);
      
      char resultData[];
      string resultHeaders;
      
      // Timeout 3000ms. Agar EA tidak hang (macet) jika server lambat membalas.
      int res = WebRequest("POST", m_api_url, headers, 3000, postData, resultData, resultHeaders);
      
      if(res == 200)
      {
         Print("[Gemini Bridge] Data Setup terkirim sukses!");
         return true;
      }
      else
      {
         Print("[Gemini Bridge] Gagal mengirim data. Error HTTP: ", res);
         // Error 4060 biasanya karena Allow WebRequest belum dicentang di MT5
         return false;
      }
   }

private:
   // Merakit string JSON secara manual agar ringan & tidak butuh library eksternal
   string FormatJSON(GeminiSetupData &d)
   {
      string json = "{";
      json += "\"symbol\":\"" + d.symbol + "\",";
      json += "\"timeframe\":\"" + d.timeframe + "\",";
      json += StringFormat("\"bid\":%.2f,", d.bid_price);
      json += StringFormat("\"ask\":%.2f,", d.ask_price);
      json += StringFormat("\"buy_score\":%.0f,", d.buy_score);
      json += StringFormat("\"sell_score\":%.0f,", d.sell_score);
      json += StringFormat("\"adx\":%.1f,", d.adx_value);
      json += StringFormat("\"spread\":%d,", d.spread_points);
      json += "\"zone_status\":\"" + d.zone_status + "\",";
      json += StringFormat("\"supply_top\":%.2f,", d.supply_top);
      json += StringFormat("\"supply_bot\":%.2f,", d.supply_bot);
      json += StringFormat("\"demand_top\":%.2f,", d.demand_top);
      json += StringFormat("\"demand_bot\":%.2f,", d.demand_bot);
      
      // Mengubah boolean indikator menjadi String agar dibaca mudah oleh LLM
      json += "\"indi_ema\":\"" + (string)(d.ema_bull ? "BULLISH" : "BEARISH") + "\",";
      json += "\"indi_macd\":\"" + (string)(d.macd_bull ? "BULLISH" : "BEARISH") + "\",";
      json += "\"indi_rsi\":\"" + (string)(d.rsi_bull ? "BULLISH" : "BEARISH") + "\",";
      json += "\"indi_stoch\":\"" + (string)(d.stoch_bull ? "BULLISH" : "BEARISH") + "\"";
      json += "}";
      
      return json;
   }
};

// Global Instance
CGeminiBridge GeminiAI("http://127.0.0.1:5000/api/analyze-setup");
