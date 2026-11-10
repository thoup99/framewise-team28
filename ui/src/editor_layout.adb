with Editor_Project_Panel;
with Editor_Preview_Panel;
with Editor_Timeline_Panel;
with Adi.Core; use Adi.Core;
with Adi.CSS_Styles; use Adi.CSS_Styles;
with Adi.Widget; use Adi.Widget;
with Adi.Widget_Styles; use Adi.Widget_Styles;
with Adi.Window; use Adi.Window;
with Timeline_View;
with Editor_Split;
with Editor_Context; use Editor_Context;
with Editor_Styles; use Editor_Styles;
with Editor_Widgets; use Editor_Widgets;
with Editor_Controller; use Editor_Controller;
with Editor_Dialogs;
with Editor_Console;
with Editor_Export;
with Editor_Tooltips;

package body Editor_Layout is
   use type Buttons.Button_Handle;
   use type Labels.Label_Handle;
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
              ((Row_Style with delta Flex_Wrap => Set (Wrap),
                Align_Items => Set (Align_Items_Value'(Center)))).Build);
         end loop;
      end;

      Set_Part_Style (+Workspace, Main_Part, Style.Base
        ((Row_Style with delta Flex_Grow => Set (1.0))).Build);
      Set_Part_Style (+Bin, Main_Part, Style.Base
        ((Panel_Style with delta Overflow_Y => Set (Overflow_Auto))).Build);
      Set_Part_Style (+Monitor, Main_Part, Style.Base
        ((Panel_Style with delta Flex_Grow => Set (1.0), Overflow_Y => Set (Overflow_Auto))).Build);
   end Create_Containers;

   procedure Build_Menu_Bar is
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
   end Build_Menu_Bar;

   procedure Arrange_Panels is
   begin
      --  Compose the panels here so builders own only their own contents.
      Add_Child (+Workspace, +Bin);
      Add_Child (+Workspace, +Monitor);
      Add_Child (+Main_Split, +Workspace);
      Add_Child (+Main_Split, +Lower);

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

   procedure Style_Menu (Menu : Menus.Menu_Handle) is
   begin
      Menus.Set_Menu_Part_Styles (Menu, Popup_Menu_Styles);
      Menus.Set_Item_Part_Styles (Menu, Menu_Item_Styles);
   end Style_Menu;

   procedure Build_File_Menu is
   begin
      File_Menu := Menus.Create_Handle;
      Menus.Attach_Window (File_Menu, W);
      Style_Menu (File_Menu);
      Reset_File_Menu;
   end Build_File_Menu;

   procedure Build is
   begin
      Create_Containers;
      Build_Menu_Bar;
      Editor_Project_Panel.Build;
      Editor_Preview_Panel.Build;
      Editor_Timeline_Panel.Build;
      Arrange_Panels;
      Editor_Dialogs.Build;
      Editor_Console.Build;
      Editor_Export.Build;
      Build_File_Menu;
      Menus.Connect_Item_Selected (File_Menu, Menu_Selected'Access);
      Clip_Menu := Menus.Create_Handle;
      Menus.Attach_Window (Clip_Menu, W);
      Style_Menu (Clip_Menu);
      Menus.Connect_Item_Selected (Clip_Menu, Clip_Menu_Selected'Access);
      Connect_Context_Menu (+Tracks, Show_Clip_Menu'Access);
      Connect_Key_Down (W, Key_Down'Access);
      Connect_Close_Request (W, Close_Requested'Access);
      Editor_Tooltips.Register (+Start_Button, "Go to the beginning (Home).");
      Editor_Tooltips.Register (+Play_Button, "Playback is not available yet.");
      Editor_Tooltips.Register (+End_Button, "Go to the project end (End).");
      Set_Root (W, +Root);
      Editor_Tooltips.Build;
   end Build;
end Editor_Layout;
