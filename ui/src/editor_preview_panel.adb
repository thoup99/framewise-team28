with Adi.Core; use Adi.Core;
with Adi.CSS_Styles; use Adi.CSS_Styles;
with Adi.Widget; use Adi.Widget;
with Adi.Widget_Styles; use Adi.Widget_Styles;
with Editor_Context; use Editor_Context;
with Editor_Styles; use Editor_Styles;
with Editor_Widgets; use Editor_Widgets;
with Adi.Image;

package body Editor_Preview_Panel is
   use type Buttons.Button_Handle;
   use type Labels.Label_Handle;
   use type Boxes.Box_Handle;

   procedure Build is
   begin
      Add_Label (+Monitor, "Video Preview");
      Preview := Make_Label (+Monitor, "");
      Set_Part_Style (+Preview, Main_Part, Style.Base
        ((Flex_Grow => Set (1.0), Height => Set (Size (Px (0.0))), Min_Height => Set (Size (Px (40.0))),
          Padding => Set (CSS_Box (Px (24.0))),
          Background_Color => Set_Bg (RGB (0, 0, 0)), others => <>)).Build);

      Set_Part_Style (+Playback_Row, Main_Part, Style.Base
        ((Row_Style with delta Justify_Content => Set (Justify_Content_Value'(Center)),
          Align_Items => Set (Align_Items_Value'(Center)))).Build);
      Add_Child (+Monitor, +Playback_Row);

      Start_Icon := Adi.Image.Load_SVG_Path
        ("M10 3 L2 10 L10 17 Z M19 3 L11 10 L19 17 Z", (20.0, 20.0),
         Fill => (220, 230, 245, 255));
      Play_Icon := Adi.Image.Load_SVG_Path
        ("M2 3 L10 10 L2 17 Z M13 3 H15 V17 H13 Z M18 3 H20 V17 H18 Z",
         (22.0, 20.0), Fill => (120, 135, 155, 255));
      End_Icon := Adi.Image.Load_SVG_Path
        ("M2 3 L10 10 L2 17 Z M11 3 L19 10 L11 17 Z", (20.0, 20.0),
         Fill => (220, 230, 245, 255));

      Start_Button := Make_Button (+Playback_Row, "");
      Play_Button := Make_Button (+Playback_Row, "");
      End_Button := Make_Button (+Playback_Row, "");
      Buttons.Set_Icon (Start_Button, Adi.Image.To_Handle (Start_Icon));
      Buttons.Set_Icon (Play_Button, Adi.Image.To_Handle (Play_Icon));
      Buttons.Set_Icon (End_Button, Adi.Image.To_Handle (End_Icon));

      declare
         Transport : constant array (1 .. 3) of Buttons.Button_Handle :=
           [Start_Button, Play_Button, End_Button];
      begin
         for H of Transport loop
            Set_Part_Style (+H, Main_Part, Style.Base
              ((Display => Set (Flex), Flex_Direction => Set (Row),
                Justify_Content => Set (Justify_Content_Value'(Center)),
                Align_Items => Set (Align_Items_Value'(Center)),
                Width => Set (Size (Px (44.0))), Height => Set (Size (Px (36.0))),
                Flex_Shrink => Set (0.0),
                Background_Color => Set_Bg (RGB (38, 50, 67)), others => <>)).Build);
            Set_Part_Style (+H, Icon_Part, Style.Base
              ((Width => Set (Size (Px (22.0))), Height => Set (Size (Px (20.0))), others => <>)).Build);
         end loop;
      end;

      --  Playback is intentionally unavailable until the media milestone.
      Set_State (+Play_Button, State_Disabled, True);
   end Build;
end Editor_Preview_Panel;
