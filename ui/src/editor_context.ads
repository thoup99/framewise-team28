with Ada.Strings.Unbounded;
with Adi.App;
with Adi.Image;
with Adi.Widget.Box;
with Adi.Widget.Button;
with Adi.Widget.Combo_Box;
with Adi.Widget.Context_Menu;
with Adi.Widget.Dialog;
with Adi.Widget.Label;
with Adi.Widget.Text_Editor;
with Adi.Widget.Text_Input;
with Adi.Window; use Adi.Window;
with Framewise.Session;
with Timeline_View;
with Editor_Split;

package Editor_Context is
   package FS renames Framewise.Session;
   package US renames Ada.Strings.Unbounded;
   package Boxes renames Adi.Widget.Box;
   package Buttons renames Adi.Widget.Button;
   package Labels renames Adi.Widget.Label;
   package Inputs renames Adi.Widget.Text_Input;
   package Combos renames Adi.Widget.Combo_Box;
   package Menus renames Adi.Widget.Context_Menu;
   package Dialogs renames Adi.Widget.Dialog;

   --  One backend session owns the document. The remaining values are UI state
   --  and widget handles shared by this single-window editor.
   A : Adi.App.App;
   W : Adi.Window.Window_Handle;
   Editor : FS.Session;
   Reply : FS.Response;

   --  Widgets are owned by the window tree; handles let callbacks reach them.
   Tracks : Timeline_View.Views.Handle;
   Preview, Status, Tool_Status : Labels.Label_Handle;
   Cursor_Time_Input, Snap_Interval_Input : Inputs.Text_Input_Handle;
   Sources : Adi.Widget.Text_Editor.Text_Editor_Handle;
   Source_Choice, Track_Choice, Kind_Choice : Combos.Combo_Box_Handle;
   File_Menu, Clip_Menu : Menus.Menu_Handle;
   Form, Confirm : Dialogs.Dialog_Handle;
   Form_Content : Boxes.Box_Handle;

   Console_Dialog : Dialogs.Dialog_Handle;
   Console_Panel : Boxes.Box_Handle;
   Console_Run_Button, Console_Close_Button : Buttons.Button_Handle;
   Console_Input : Inputs.Text_Input_Handle;
   Console_Output : Adi.Widget.Text_Editor.Text_Editor_Handle;
   Console_Button : Buttons.Button_Handle;

   type Box_Array is array (Positive range <>) of Boxes.Box_Handle;
   type Dialog_Array is array (Positive range <>) of Dialogs.Dialog_Handle;
   type Input_Array is array (Positive range 1 .. 3) of Inputs.Text_Input_Handle;
   type Label_Array is array (Positive range 1 .. 3) of Labels.Label_Handle;
   Values : Input_Array;
   Captions : Label_Array;

   File_Button, Add_Track_Button, Place_Button, Undo_Button,
     Delete_Button, Razor_Button, Move_Button,
     Zoom_In, Zoom_Out, Scroll_Left, Scroll_Right,
     Start_Button, Play_Button, End_Button : Buttons.Button_Handle;

   type Media_Filter is (All_Media, Video_Media, Audio_Media);
   type Filter_Button_Array is array (Media_Filter) of Buttons.Button_Handle;
   Filter_Buttons : Filter_Button_Array;
   Current_Filter : Media_Filter := All_Media;

   --  Dialog state and unsaved-change bookkeeping are independent of the document.
   type Form_Mode is (Import_Media, Add_Track, Place_Clip, Move_Clip, Project_Settings);
   Mode : Form_Mode := Import_Media;

   type Pending_Action is (Nothing, New_Project, Open_Project, Close_Editor);
   Pending : Pending_Action := Nothing;
   Project_Path, Saved_History : US.Unbounded_String;
   Form_Target : US.Unbounded_String;
   Dirty : Boolean := False;
   Allow_Close : Boolean := False;

   Root, Menu_Row, Filter_Row, Playback_Row, Bin, Monitor, Lower, Timeline_Tools,
     Placement_Row, Track_Scroll : Boxes.Box_Handle;
   Workspace, Main_Split : Editor_Split.Views.Handle;

   --  Keep icon owners alive while their buttons reference the image handles.
   Start_Icon, Play_Icon, End_Icon : Adi.Image.Image_Owner;
end Editor_Context;
