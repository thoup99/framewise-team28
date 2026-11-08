with Adi.Core; use Adi.Core;
with Adi.CSS_Styles; use Adi.CSS_Styles;
with Adi.Widget_Styles; use Adi.Widget_Styles;
with Editor_Context; use Editor_Context;
with Adi.Widget; use Adi.Widget;

package body Editor_Styles is
   use type Buttons.Button_Handle;
   use type Combos.Combo_Box_Handle;

   procedure Style_Button (H : Buttons.Button_Handle) is
   begin
      Set_Part_Style (+H, Main_Part, Style.Base
        ((Background_Color => Set_Bg (RGB (38, 50, 67)),
          Padding => Set (CSS_Box (Px (7.0), Px (10.0))),
          Border_Radius => Set (Radius (Px (3.0))), others => <>)).Build);
      Set_Part_Style (+H, Label_Part, Style.Base (Text_Style).Build);
   end Style_Button;

   procedure Style_Combo (H : Combos.Combo_Box_Handle) is
   begin
      Set_Part_Style (+H, Main_Part, Style.Base
        ((Display => Set (Flex), Flex_Direction => Set (Row),
          Width => Set (Size (Px (200.0))),
          Height => Set (Size (Px (38.0))), Flex_Shrink => Set (0.0),
          Background_Color => Set_Bg (RGB (38, 50, 67)),
          Padding => Set (CSS_Box (Px (6.0))), others => <>)).Build);
      Set_Part_Style (+H, Text_Part, Style.Base (Text_Style).Build);
      Combos.Set_Dropdown_Part_Styles (H,
        (Main_Part => (Style => Style.Base (Panel_Style).Build, Enabled => True), others => <>));
      Combos.Set_Option_Row_Part_Styles (H,
        (Label_Part => (Style => Style.Base (Text_Style).Build, Enabled => True), others => <>));
   end Style_Combo;
end Editor_Styles;
