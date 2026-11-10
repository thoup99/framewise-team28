with Adi.Core; use Adi.Core;
with Adi.CSS_Styles; use Adi.CSS_Styles;
with Adi.Widget; use Adi.Widget;
with Adi.Widget_Styles; use Adi.Widget_Styles;
with Editor_Context; use Editor_Context;
with Editor_Styles; use Editor_Styles;
with Editor_Widgets; use Editor_Widgets;
with Editor_Controller; use Editor_Controller;
with Timeline_View;
with Editor_Tooltips;

package body Editor_Timeline_Panel is
   use type Buttons.Button_Handle;
   use type Labels.Label_Handle;
   use type Inputs.Text_Input_Handle;
   use type Combos.Combo_Box_Handle;
   use type Timeline_View.Views.Handle;
   use type Boxes.Box_Handle;

   procedure Build_Tools is
   begin
      Add_Track_Button := Make_Button (+Timeline_Tools, "Add Track", Show_Tooltip => False);
      Undo_Button := Make_Button (+Timeline_Tools, "Undo");
      Razor_Button := Make_Button (+Timeline_Tools, "Razor");
      Set_Part_Style (+Razor_Button, Main_Part, Style.Base
        ((Background_Color => Set_Bg (RGB (38, 50, 67)),
          Padding => Set (CSS_Box (Px (7.0), Px (10.0))),
          Border_Radius => Set (Radius (Px (3.0))), others => <>))
        .On_Selected ((Background_Color => Set_Bg (RGB (52, 112, 204)), others => <>)).Build);
      Move_Button := Make_Button (+Timeline_Tools, "Move Clip", Show_Tooltip => False);
      Delete_Button := Make_Button (+Timeline_Tools, "Delete Clip");
      Zoom_Out := Make_Button (+Timeline_Tools, "Zoom -", Show_Tooltip => False);
      Zoom_In := Make_Button (+Timeline_Tools, "Zoom +", Show_Tooltip => False);
      Scroll_Left := Make_Button (+Timeline_Tools, "Earlier", Show_Tooltip => False);
      Scroll_Right := Make_Button (+Timeline_Tools, "Later", Show_Tooltip => False);
      Add_Label (+Timeline_Tools, "Snap (s)");
      Snap_Interval_Input := Inputs.Create_Handle ("0.5");
      Inputs.Set_Min_Visible_Chars (Snap_Interval_Input, 6);
      Inputs.Set_Context_Menu_Part_Styles (Snap_Interval_Input, Popup_Menu_Styles);
      Inputs.Set_Context_Menu_Item_Part_Styles
        (Snap_Interval_Input, Menu_Item_Styles);
      Set_Part_Style (+Snap_Interval_Input, Main_Part, Style.Base
        ((Width => Set (Size (Px (86.0))), Flex_Shrink => Set (0.0),
          Background_Color => Set_Bg (RGB (38, 50, 67)),
          Padding => Set (CSS_Box (Px (6.0))), others => <>)).Build);
      Style_Input_Text (+Snap_Interval_Input);
      Add_Child (+Timeline_Tools, +Snap_Interval_Input);

      Inputs.Connect_Changed (Snap_Interval_Input, Snap_Interval_Changed'Access);

      Add_Label (+Timeline_Tools, "Timeline Cursor (s)");
      Cursor_Time_Input := Inputs.Create_Handle ("0");
      Set_Part_Style (+Cursor_Time_Input, Main_Part, Style.Base
        ((Width => Set (Size (Px (110.0))), Flex_Shrink => Set (0.0),
          Background_Color => Set_Bg (RGB (38, 50, 67)),
          Padding => Set (CSS_Box (Px (6.0))), others => <>)).Build);
      Style_Input_Text (+Cursor_Time_Input, Selection => False);
      Inputs.Connect_Changed (Cursor_Time_Input, Cursor_Time_Changed'Access);
      Add_Child (+Timeline_Tools, +Cursor_Time_Input);
      Editor_Tooltips.Register (+Cursor_Time_Input, "Jump to a position in seconds. Invalid values stay red.");

   end Build_Tools;

   procedure Build_Placement_Row is
   begin
      Add_Label (+Placement_Row, "Select media");
      Source_Choice := Combos.Create_Handle;
      Style_Combo (Source_Choice);
      Add_Child (+Placement_Row, +Source_Choice);

      Add_Label (+Placement_Row, "Target track");
      Track_Choice := Combos.Create_Handle;
      Style_Combo (Track_Choice);
      Add_Child (+Placement_Row, +Track_Choice);
      Place_Button := Make_Button (+Placement_Row, "Add Selected Media to Track");
      Tool_Status := Make_Label (+Placement_Row, "");
      Set_Visible (+Tool_Status, False);

   end Build_Placement_Row;

   procedure Build_Track_Viewport is
   begin
      Tracks := Timeline_View.Views.New_Widget;
      Set_Flag (+Tracks, Clickable, True);
      Set_Flag (+Tracks, Focusable, True);
      declare
         V : Timeline_View.Views.Ref := Timeline_View.Views.Borrow (Tracks);
      begin
         V.Read_Sequence := Read_Sequence'Access;
         V.Submit_Command := Execute_Line'Access;
         V.Preview_Changed := Show_Preview'Access;
         V.Selection_Changed := Clip_Selected'Access;
      end;

      --  Reserve a gutter outside the clip hit area for the mouse scrollbar.
      Set_Part_Style (+Track_Scroll, Main_Part, Style.Base
        ((Flex_Grow => Set (1.0), Min_Height => Set (Size (Px (80.0))),
          Overflow_Y => Set (Overflow_Auto), others => <>)).Build);
      Set_Flag (+Track_Scroll, Scrollable, True);
      --  Route presses in the gutter to the scroll container rather than
      --  the clickable split pane ancestor.
      Set_Flag (+Track_Scroll, Clickable, True);
      Style_Scrollbar (+Track_Scroll);

      Set_Part_Style (+Tracks, Items_Part, Style.Base
        ((Background_Color => Set_Bg (RGB (88, 220, 185)), others => <>)).Build);
      Set_Part_Style (+Tracks, Label_Part, Style.Base (Text_Style).Build);
      Set_Part_Style (+Tracks, Cursor_Part, Style.Base
        ((Background_Color => Set_Bg (RGB (255, 225, 130)), others => <>)).Build);
      Set_Part_Style (+Tracks, Custom_Part, Style.Base
        ((Background_Color => Set_Bg (RGB (38, 49, 65)), others => <>)).Build);
      Set_Part_Style (+Tracks, Indicator_Part, Style.Base
        ((Background_Color => Set_Bg (RGB (46, 104, 173)), others => <>)).Build);
      Set_Part_Style (+Tracks, Selected_Part, Style.Base
        ((Background_Color => Set_Bg (RGB (176, 119, 37)), others => <>)).Build);

      Add_Child (+Track_Scroll, +Tracks);
   end Build_Track_Viewport;

   procedure Build is
   begin
      Build_Tools;
      Build_Placement_Row;
      Build_Track_Viewport;
      declare
         Sections : constant Box_Array := [Timeline_Tools, Placement_Row, Track_Scroll];
      begin
         for H of Sections loop
            Add_Child (+Lower, +H);
         end loop;
      end;
   end Build;
end Editor_Timeline_Panel;
