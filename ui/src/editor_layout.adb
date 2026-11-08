with Adi.Core; use Adi.Core;
with Adi.CSS_Styles; use Adi.CSS_Styles;
with Adi.Widget; use Adi.Widget;
with Adi.Widget_Styles; use Adi.Widget_Styles;
with Adi.Window; use Adi.Window;
with Timeline_View;
with Editor_Split;
with Adi.Widget.Text_Editor;
with Editor_Context; use Editor_Context;
with Adi.Image;
with Editor_Styles; use Editor_Styles;
with Editor_Widgets; use Editor_Widgets;
with Editor_Controller; use Editor_Controller;
with Editor_Dialogs;
with Editor_Console;

package body Editor_Layout is
   use type Buttons.Button_Handle;
   use type Labels.Label_Handle;
   use type Inputs.Text_Input_Handle;
   use type Combos.Combo_Box_Handle;
   use type Adi.Widget.Text_Editor.Text_Editor_Handle;
   use type Timeline_View.Views.Handle;
   use type Editor_Split.Views.Handle;
   use type Boxes.Box_Handle;

   procedure Create_Containers is
   begin
      Root := Boxes.Create_Handle;
      Menu_Row := Boxes.Create_Handle;
      Filter_Row := Boxes.Create_Handle;
      Playback_Row := Boxes.Create_Handle;
      Lower := Boxes.Create_Handle;
      Bin := Boxes.Create_Handle;
      Monitor := Boxes.Create_Handle;
      Timeline_Tools := Boxes.Create_Handle;
      Placement_Row := Boxes.Create_Handle;
      Track_Scroll := Boxes.Create_Handle;
      Workspace := Editor_Split.Views.New_Widget;
      Main_Split := Editor_Split.Views.New_Widget;

      Set_Part_Style (+Lower, Main_Part, Style.Base
        ((Panel_Style with delta Overflow_Y => Set (Overflow_Auto))).Build);
      Set_Part_Style (+Root, Main_Part, Style.Base (Panel_Style).Build);
      declare
         Rows : constant Box_Array := [Menu_Row, Filter_Row, Timeline_Tools, Placement_Row];
      begin
         for H of Rows loop
            Set_Part_Style (+H, Main_Part, Style.Base
              ((Row_Style with delta Flex_Wrap => Set (Wrap))).Build);
         end loop;
      end;

      Set_Part_Style (+Workspace, Main_Part, Style.Base
        ((Row_Style with delta Flex_Grow => Set (1.0))).Build);
      Set_Part_Style (+Bin, Main_Part, Style.Base
        ((Panel_Style with delta Overflow_Y => Set (Overflow_Auto))).Build);
      Set_Part_Style (+Monitor, Main_Part, Style.Base
        ((Panel_Style with delta Flex_Grow => Set (1.0), Overflow_Y => Set (Overflow_Auto))).Build);
   end Create_Containers;

   procedure Build_Project_Files is
   begin
      File_Button := Make_Button (+Menu_Row, "File");
      declare
         Spacer : constant Boxes.Box_Handle := Boxes.Create_Handle;
      begin
         Set_Part_Style (+Spacer, Main_Part, Style.Base
           ((Flex_Grow => Set (1.0), others => <>)).Build);
         Add_Child (+Menu_Row, +Spacer);
      end;
      Console_Button := Make_Button (+Menu_Row, "Console");

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
   end Build_Project_Files;

   procedure Build_Preview is
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
      Add_Child (+Workspace, +Bin);
      Add_Child (+Workspace, +Monitor);
   end Build_Preview;

   --  Reserve the scroll gutter outside the timeline hit area so dragging
   --  the scrollbar cannot be mistaken for a clip or splitter interaction.
   procedure Build_Timeline is
   begin
      Add_Track_Button := Make_Button (+Timeline_Tools, "Add Track");
      Undo_Button := Make_Button (+Timeline_Tools, "Undo");
      Razor_Button := Make_Button (+Timeline_Tools, "Razor");
      Set_Part_Style (+Razor_Button, Main_Part, Style.Base
        ((Background_Color => Set_Bg (RGB (38, 50, 67)),
          Padding => Set (CSS_Box (Px (7.0), Px (10.0))),
          Border_Radius => Set (Radius (Px (3.0))), others => <>))
        .On_Selected ((Background_Color => Set_Bg (RGB (52, 112, 204)), others => <>)).Build);
      Move_Button := Make_Button (+Timeline_Tools, "Move Clip");
      Delete_Button := Make_Button (+Timeline_Tools, "Delete Clip");
      Zoom_Out := Make_Button (+Timeline_Tools, "Zoom -");
      Zoom_In := Make_Button (+Timeline_Tools, "Zoom +");
      Scroll_Left := Make_Button (+Timeline_Tools, "Earlier");
      Scroll_Right := Make_Button (+Timeline_Tools, "Later");
      Add_Label (+Timeline_Tools, "Snap (s)");
      Snap_Interval_Input := Inputs.Create_Handle ("0.5");
      Inputs.Set_Min_Visible_Chars (Snap_Interval_Input, 6);
      Inputs.Set_Context_Menu_Part_Styles (Snap_Interval_Input,
        (Main_Part => (Style => Style.Base (Floating_Panel_Style).Build, Enabled => True), others => <>));
      Inputs.Set_Context_Menu_Item_Part_Styles (Snap_Interval_Input,
        (Main_Part => (Style => Style.Base
           ((Padding => Set (CSS_Box (Px (6.0), Px (8.0))), others => <>))
           .On_Hover ((Background_Color => Set_Bg (RGB (45, 78, 119)), others => <>))
           .On_Selected ((Background_Color => Set_Bg (RGB (45, 78, 119)), others => <>)).Build,
          Enabled => True),
         Label_Part => (Style => Style.Base (Text_Style).Build, Enabled => True), others => <>));
      Set_Part_Style (+Snap_Interval_Input, Main_Part, Style.Base
        ((Width => Set (Size (Px (86.0))), Flex_Shrink => Set (0.0),
          Background_Color => Set_Bg (RGB (38, 50, 67)),
          Padding => Set (CSS_Box (Px (6.0))), others => <>)).Build);
      Set_Part_Style (+Snap_Interval_Input, Text_Part, Style.Base (Text_Style).Build);
      Set_Part_Style (+Snap_Interval_Input, Cursor_Part, Style.Base
        ((Background_Color => Set_Bg (RGB (240, 245, 255)), others => <>)).Build);
      Set_Part_Style (+Snap_Interval_Input, Selected_Part, Style.Base
        ((Background_Color => Set_Bg (RGB (52, 112, 204)), others => <>)).Build);
      Add_Child (+Timeline_Tools, +Snap_Interval_Input);

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

      Inputs.Connect_Changed (Snap_Interval_Input, Snap_Interval_Changed'Access);

      Set_Part_Style (+Track_Scroll, Main_Part, Style.Base
        ((Flex_Grow => Set (1.0), Min_Height => Set (Size (Px (80.0))),
          Overflow_Y => Set (Overflow_Auto), others => <>)).Build);
      Set_Flag (+Track_Scroll, Scrollable, True);
      --  Route presses in the gutter to the scroll container rather than
      --  the clickable split pane ancestor.
      Set_Flag (+Track_Scroll, Clickable, True);
      Set_Part_Style (+Track_Scroll, Scroll_Part, Style.Base
        ((Width => Set (Size (Px (14.0))),
          Background_Color => Set_Bg (RGB (22, 29, 40)), others => <>)).Build);
      Set_Part_Style (+Track_Scroll, Knob_Part, Style.Base
        ((Width => Set (Size (Px (10.0))), Min_Height => Set (Size (Px (24.0))),
          Background_Color => Set_Bg (RGB (115, 135, 160)),
          Border_Radius => Set (Radius (Px (5.0))), others => <>))
        .On_Hover ((Background_Color => Set_Bg (RGB (145, 170, 200)), others => <>))
        .On_Press ((Background_Color => Set_Bg (RGB (52, 112, 204)), others => <>)).Build);

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
      declare
         Sections : constant Box_Array := [Timeline_Tools, Placement_Row, Track_Scroll];
      begin
         for H of Sections loop
            Add_Child (+Lower, +H);
         end loop;
      end;
      Add_Child (+Main_Split, +Workspace);
      Add_Child (+Main_Split, +Lower);
   end Build_Timeline;

   procedure Arrange_Panels is
   begin
      declare
         V : Editor_Split.Views.Ref := Editor_Split.Views.Borrow (Workspace);
         M : Editor_Split.Views.Ref := Editor_Split.Views.Borrow (Main_Split);
      begin
         V.First := +Bin;
         V.Second := +Monitor;
         V.Fraction := 0.31;
         V.Minimum_First := 240.0;
         V.Minimum_Second := 300.0;
         M.First := +Workspace;
         M.Second := +Lower;
         M.Vertical := True;
         M.Fraction := 0.70;
         M.Minimum_First := 180.0;
         M.Minimum_Second := 220.0;
      end;
      Set_Part_Style (+Main_Split, Main_Part, Style.Base
        ((Flex_Grow => Set (1.0), Height => Set (Size (Px (0.0))), others => <>)).Build);
      Set_Flag (+Workspace, Clickable, True);
      Set_Flag (+Main_Split, Clickable, True);
      Set_Part_Style (+Workspace, Indicator_Part, Style.Base
        ((Background_Color => Set_Bg (RGB (8, 33, 71)), others => <>)).Build);
      Set_Part_Style (+Main_Split, Indicator_Part, Style.Base
        ((Background_Color => Set_Bg (RGB (8, 33, 71)), others => <>)).Build);

      Add_Child (+Root, +Menu_Row);

      Add_Child (+Root, +Main_Split);
      Status := Make_Label (+Root, "Ready. Import files and add a track, or open a .fw project.");
   end Arrange_Panels;

   procedure Build_File_Menu is
   begin
      File_Menu := Menus.Create_Handle;
      Menus.Attach_Window (File_Menu, W);
      Menus.Set_Menu_Part_Styles (File_Menu,
        (Main_Part => (Style => Style.Base (Floating_Panel_Style).Build, Enabled => True), others => <>));
      Menus.Set_Item_Part_Styles (File_Menu,
        (Main_Part =>
           (Style => Style.Base
              ((Padding => Set (CSS_Box (Px (6.0), Px (8.0))), others => <>))
              .On_Hover
                ((Background_Color => Set_Bg (RGB (45, 78, 119)), others => <>))
              .On_Selected
                ((Background_Color => Set_Bg (RGB (45, 78, 119)), others => <>)).Build,
            Enabled => True),
         Label_Part => (Style => Style.Base (Text_Style).Build, Enabled => True),
         others => <>));
      Menus.Add_Item (File_Menu, "New Project     Ctrl+N");
      Menus.Add_Item (File_Menu, "Open Project    Ctrl+O");
      Menus.Add_Item (File_Menu, "Save            Ctrl+S");
      Menus.Add_Item (File_Menu, "Save As   Ctrl+Shift+S");
      Menus.Add_Item (File_Menu, "Import Files...");
      Menus.Add_Item (File_Menu, "Project Settings...");
      Menus.Add_Item (File_Menu, "Export Video...");
      Menus.Add_Item (File_Menu, "Exit");
   end Build_File_Menu;

   procedure Build is
   begin
      Create_Containers;
      Build_Project_Files;
      Build_Preview;
      Build_Timeline;
      Arrange_Panels;
      Editor_Dialogs.Build;
      Editor_Console.Build;
      Build_File_Menu;
      Menus.Connect_Item_Selected (File_Menu, Menu_Selected'Access);
      Connect_Key_Down (W, Key_Down'Access);
      Connect_Close_Request (W, Close_Requested'Access);
      Set_Root (W, +Root);
   end Build;
end Editor_Layout;
