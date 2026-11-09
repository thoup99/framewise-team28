with Adi.Core; use Adi.Core;
with Adi.CSS_Styles; use Adi.CSS_Styles;
with Adi.Widget_Styles; use Adi.Widget_Styles;
with Editor_Context; use Editor_Context;
with Adi.Widget; use Adi.Widget;

package body Editor_Styles is
   use type Buttons.Button_Handle;
   use type Combos.Combo_Box_Handle;

   function Menu_Item_Styles
     (Highlight_Selection : Boolean := True;
      Dim_Disabled : Boolean := False) return Part_Style_Array
   is
      Item : Style_Builder := Style.Base
        ((Padding => Set (CSS_Box (Px (6.0), Px (8.0))), others => <>))
        .On_Hover ((Background_Color => Set_Bg (RGB (45, 78, 119)), others => <>));
      Label : Style_Builder := Style.Base (Text_Style);
   begin
      if Highlight_Selection then
         Item := Item.On_Selected
           ((Background_Color => Set_Bg (RGB (45, 78, 119)), others => <>));
      end if;

      if Dim_Disabled then
         Label := Label.On_Disabled ((Color => Set (RGB (145, 155, 170)), others => <>));
      end if;

      return
        (Main_Part => (Style => Item.Build, Enabled => True),
         Label_Part => (Style => Label.Build, Enabled => True), others => <>);
   end Menu_Item_Styles;

   procedure Style_Input_Text (H : Widget_Handle; Selection : Boolean := True) is
   begin
      Set_Part_Style (H, Text_Part, Style.Base (Text_Style).Build);
      Set_Part_Style (H, Cursor_Part, Style.Base
        ((Background_Color => Set_Bg (RGB (240, 245, 255)), others => <>)).Build);

      if Selection then
         Set_Part_Style (H, Selected_Part, Style.Base
           ((Background_Color => Set_Bg (RGB (52, 112, 204)), others => <>)).Build);
      end if;
   end Style_Input_Text;

   procedure Style_Scrollbar (H : Widget_Handle; Highlight_Interactions : Boolean := True) is
      Knob : Style_Builder := Style.Base
        ((Width => Set (Size (Px (10.0))), Min_Height => Set (Size (Px (24.0))),
          Background_Color => Set_Bg (RGB (115, 135, 160)), others => <>));
   begin
      Set_Part_Style (H, Scroll_Part, Style.Base
        ((Width => Set (Size (Px (14.0))),
          Background_Color => Set_Bg (RGB (22, 29, 40)), others => <>)).Build);

      if Highlight_Interactions then
         Knob := Style.Base
           ((Width => Set (Size (Px (10.0))), Min_Height => Set (Size (Px (24.0))),
             Background_Color => Set_Bg (RGB (115, 135, 160)),
             Border_Radius => Set (Radius (Px (5.0))), others => <>))
           .On_Hover ((Background_Color => Set_Bg (RGB (145, 170, 200)), others => <>))
           .On_Press ((Background_Color => Set_Bg (RGB (52, 112, 204)), others => <>));
      end if;

      Set_Part_Style (H, Knob_Part, Knob.Build);
   end Style_Scrollbar;

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
