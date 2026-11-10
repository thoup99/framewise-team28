with Editor_Project_Actions;
with Editor_Timeline_Actions;
with Editor_Shortcuts;
with Adi.Core;
with Adi.Widget; use Adi.Widget;
with Adi.Window; use Adi.Window;
with Adi.OS;
with Adi.SDL.Events;
with Editor_Context; use Editor_Context;

package Editor_Controller is
   --  Stable callbacks delegate to focused action modules.
   --  Document edits retain the same session execution and logging boundary.
   procedure Update_Filter_Buttons;

   procedure Reset_File_Menu
     renames Editor_Project_Actions.Reset_File_Menu;

   procedure Tell (Text : String);

   --  Surface validation failures that occur before a session command runs.
   procedure Report_Editor_Error (Action, Message : String);

   procedure Cursor_Time_Changed (Input : Widget_Handle; Text : String)
     renames Editor_Timeline_Actions.Cursor_Time_Changed;

   procedure Snap_Interval_Changed (Input : Widget_Handle; Text : String)
     renames Editor_Timeline_Actions.Snap_Interval_Changed;

   function History return US.Unbounded_String;

   function Read_Sequence return FS.Sequence_View;

   procedure Show_Preview (Text : String)
     renames Editor_Timeline_Actions.Show_Preview;

   procedure Refresh_Timeline;

   procedure Execute_Line (Line : String);

   --  Console origin uses the same execution and logging boundary.
   procedure Execute_Console_Command (Line : String);

   --  Execute console commands and synchronize save/load document bookkeeping.
   procedure Execute_Console_Line (Line : String)
     renames Editor_Project_Actions.Execute_Console_Line;

   function Valid_Path (Text, Action : String) return Boolean;

   function Unique_Name (Prefix : String) return String;

   procedure Save_Selected (Files : Adi.OS.String_Array)
     renames Editor_Project_Actions.Save_Selected;

   procedure Save_Project (Save_As : Boolean := False)
     renames Editor_Project_Actions.Save_Project;

   procedure Open_Selected (Files : Adi.OS.String_Array)
     renames Editor_Project_Actions.Open_Selected;

   procedure Request_Action (Action : Pending_Action)
     renames Editor_Project_Actions.Request_Action;

   procedure Confirm_Result (Dialog : Widget_Handle; Index : Natural; Caption : String)
     renames Editor_Project_Actions.Confirm_Result;

   procedure Close_Requested (Window : Window_Handle; Allow : in out Boolean)
     renames Editor_Project_Actions.Close_Requested;

   procedure Export_Selected (Files : Adi.OS.String_Array)
     renames Editor_Project_Actions.Export_Selected;

   procedure Clip_Selected (Name : String)
     renames Editor_Timeline_Actions.Clip_Selected;

   procedure Clicked (Button : Widget_Handle);

   procedure Show_Clip_Menu (Widget : Widget_Handle; X, Y : Adi.Core.Pixel_Type)
     renames Editor_Timeline_Actions.Show_Clip_Menu;

   procedure Clip_Menu_Selected (Menu : Menus.Menu_Handle; Index : Positive; Text : String)
     renames Editor_Timeline_Actions.Clip_Menu_Selected;

   procedure Menu_Selected (Menu : Menus.Menu_Handle; Index : Positive; Text : String)
     renames Editor_Project_Actions.Menu_Selected;

   procedure Key_Down
     (Scancode : Adi.SDL.Events.SDL_Scancode;
      Keycode : Adi.SDL.Events.SDL_Keycode;
      Key_Mod : Adi.SDL.Events.SDL_Keymod;
      Repeat : Boolean; Handled : in out Boolean) renames Editor_Shortcuts.Key_Down;
end Editor_Controller;
