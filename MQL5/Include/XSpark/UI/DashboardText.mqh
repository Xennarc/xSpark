#ifndef XSPARK_UI_DASHBOARD_TEXT_MQH
#define XSPARK_UI_DASHBOARD_TEXT_MQH

// OBJ_LABEL sizes are points, while chart coordinates are pixels. Match the
// native label font with negative tenths of a point before measuring it:
// https://www.mql5.com/en/docs/objects/textsetfont
// Do not infer text width from character counts or an assumed display DPI.
int XSparkDashboardFont(string &font, const int requested, const double scale,
                        const int dpi, const int height_pixels)
{
   int points = (int)MathMax(9, MathRound(requested * scale * 96.0 / MathMax(1, dpi)));
   for(; points >= 9; points--)
   {
      if(!TextSetFont(font, -10 * points, 0))
      {
         font = "Arial";
         if(!TextSetFont(font, -10 * points, 0)) continue;
      }
      uint width = 0, height = 0;
      if(TextGetSize("Mg", width, height) && height > 0 && (int)height <= height_pixels)
         return points;
   }
   return 0; // Unknown metrics must not place unbounded text over other fields.
}

// The panel must grow with native text, not cancel the user's display scaling.
// Measure a readable 9-point baseline as well, for Wine DPI reporting mismatches.
double XSparkDashboardReadableScale(const int dpi, const int percent)
{
   double device_scale = MathMax(1.0, (double)dpi / 96.0);
   string fonts[4] = {"Arial", "Segoe UI", "Arial Bold", "Consolas"};
   for(int i = 0; i < 4; i++)
   {
      uint width = 0, height = 0;
      if(TextSetFont(fonts[i], -90, 0) && TextGetSize("Mg", width, height) && height > 0)
         device_scale = MathMax(device_scale, (double)height / 13.0);
   }
   return device_scale * MathMax(125, MathMin(200, percent)) / 100.0;
}

// These helpers use the font selected immediately above. No chart API writes.
int XSparkDashboardPrefix(const string text, const int width_pixels)
{
   int low = 0, high = StringLen(text);
   while(low < high)
   {
      const int mid = (low + high + 1) / 2;
      uint width = 0, height = 0;
      if(TextGetSize(StringSubstr(text, 0, mid), width, height) && (int)width <= width_pixels)
         low = mid;
      else high = mid - 1;
   }
   return low;
}

string XSparkDashboardFitText(const string text, const int width_pixels)
{
   if(text == "" || width_pixels <= 0) return "";
   if(XSparkDashboardPrefix(text, width_pixels) == StringLen(text)) return text;
   uint dots_width = 0, dots_height = 0;
   if(!TextGetSize("...", dots_width, dots_height) || (int)dots_width > width_pixels) return "";
   const int count = XSparkDashboardPrefix(text, width_pixels - (int)dots_width);
   return StringSubstr(text, 0, count) + "...";
}

string XSparkDashboardPixelLine(const string text, const int row, const int width_pixels,
                               const bool final_line)
{
   if(row < 0 || width_pixels <= 0) return "";
   int start = 0;
   for(int line = 0; line <= row; line++)
   {
      const string tail = StringSubstr(text, start);
      if(tail == "") return "";
      if(line == row && final_line) return XSparkDashboardFitText(tail, width_pixels);
      int count = XSparkDashboardPrefix(tail, width_pixels);
      if(count <= 0) return "";
      if(count < StringLen(tail))
         for(int k = count; k > 0; k--)
            if(StringSubstr(tail, k, 1) == " ") { count = k; break; }
      if(line == row) return StringSubstr(tail, 0, count);
      start += count;
      while(StringSubstr(text, start, 1) == " ") start++;
   }
   return "";
}
#endif
