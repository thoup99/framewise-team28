with Adi.Core; use Adi.Core;
with Adi.CSS_Styles; use Adi.CSS_Styles;
with Adi.Widget; use Adi.Widget;
with Adi.Widget_Styles; use Adi.Widget_Styles;
with Editor_Context; use Editor_Context;
with Editor_Styles; use Editor_Styles;
with Editor_Widgets; use Editor_Widgets;
with Adi.Image;
with Adi.Widget.Extension;

package body Editor_Preview_Panel is
   use type Buttons.Button_Handle;
   use type Labels.Label_Handle;
   use type Boxes.Box_Handle;

   --  A preview is scalable canvas content, not an intrinsic-size label icon.
   --  Keep the label interface for status text while drawing the image over
   --  the allocated geometry directly, without growing the panel's minimum.
   type Preview_Canvas is new Labels.Label_Widget with null record;
   overriding procedure Layout (Canvas : in out Preview_Canvas) is null;
   overriding procedure Build_Items (Canvas : in out Preview_Canvas);
   overriding function Measure_Content (Canvas : Preview_Canvas) return Size_2D is ((0.0, 0.0));
   overriding function Measure_Content_At_Width
     (Canvas : Preview_Canvas; Assigned_Width : Pixel_Type) return Size_2D is ((0.0, 0.0));
   overriding function Get_Content_Min_Size (Canvas : Preview_Canvas) return Size_2D is ((0.0, 0.0));
   overriding function Get_Content_Min_Size_At_Width
     (Canvas : Preview_Canvas; Assigned_Width : Pixel_Type) return Size_2D is ((0.0, 0.0));

   package Canvases is new Adi.Widget.Extension (Preview_Canvas);

   overriding procedure Build_Items (Canvas : in out Preview_Canvas) is
      Area : constant Rectangle := Get_Geometry (Canvas);
   begin
      Clear_Items (Canvas);
      Add_Item (Canvas, Make_Panel (Main_Part, Area, 0));
      Add_Item (Canvas, Make_Image
        (Icon_Part, Area, Labels.Get_Icon (Labels.Label_Widget (Canvas)), 1));
      Add_Item (Canvas, Make_Text
        (Label_Part, Area, Labels.Get_Text (Labels.Label_Widget (Canvas)), 2));
   end Build_Items;

   procedure Build is
   begin
      Add_Label (+Monitor, "Video Preview");
      Preview := Labels.Try_As_Label (Canvases.To_Widget_Handle (Canvases.New_Widget));
      Add_Child (+Monitor, +Preview);
      Set_Part_Style (+Preview, Label_Part, Style.Base (Text_Style).Build);
      Set_Part_Style (+Preview, Main_Part, Style.Base
        ((Flex_Grow => Set (1.0), Height => Set (Size (Px (0.0))), Min_Height => Set (Size (Px (40.0))),
          Min_Width => Set (Size (Px (0.0))),
          Justify_Content => Set (Justify_Content_Value'(Center)),
          Align_Items => Set (Align_Items_Value'(Center)),
          Padding => Set (CSS_Box (Px (0.0))),
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
