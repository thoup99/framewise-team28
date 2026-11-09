with Adi.Core; use Adi.Core;
with Adi.CSS_Styles; use Adi.CSS_Styles;
with Adi.Widget; use Adi.Widget;
with Adi.Widget_Styles; use Adi.Widget_Styles;
with Editor_Context; use Editor_Context;
with Editor_Styles; use Editor_Styles;
with Editor_Widgets; use Editor_Widgets;
with Editor_Controller; use Editor_Controller;
with Adi.Widget.Text_Editor;

package body Editor_Project_Panel is
   use type Buttons.Button_Handle;
   use type Adi.Widget.Text_Editor.Text_Editor_Handle;
   use type Boxes.Box_Handle;

   procedure Build is
   begin
      Add_Label (+Bin, "Project Files");
      Add_Child (+Bin, +Filter_Row);
      Filter_Buttons (All_Media) := Make_Button (+Filter_Row, "All");
      Filter_Buttons (Video_Media) := Make_Button (+Filter_Row, "Video");
      Filter_Buttons (Audio_Media) := Make_Button (+Filter_Row, "Audio");
      for H of Filter_Buttons loop
         Set_Part_Style (+H, Main_Part, Style.Base
           ((Background_Color => Set_Bg (RGB (38, 50, 67)),
             Padding => Set (CSS_Box (Px (7.0), Px (10.0))),
             Border_Radius => Set (Radius (Px (3.0))), others => <>))
           .On_Selected ((Background_Color => Set_Bg (RGB (52, 112, 204)), others => <>)).Build);
      end loop;
      Update_Filter_Buttons;

      Sources := Adi.Widget.Text_Editor.Create_Handle ("");
      Adi.Widget.Text_Editor.Set_Read_Only (Sources);
      Set_Part_Style (+Sources, Main_Part, Style.Base
        ((Flex_Grow => Set (1.0), Height => Set (Size (Px (0.0))), Min_Height => Set (Size (Px (40.0))),
          Background_Color => Set_Bg (RGB (20, 26, 36)), others => <>)).Build);
      Set_Part_Style (+Sources, Text_Part, Style.Base (Text_Style).Build);
      Add_Child (+Bin, +Sources);
   end Build;
end Editor_Project_Panel;
