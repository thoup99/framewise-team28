with Adi.OS;
with Adi.Widget; use Adi.Widget;
with Adi.Window; use Adi.Window;
with Editor_Context; use Editor_Context;

package Editor_Project_Actions is
   --  Project lifecycle, native file dialogs and saved-document bookkeeping.
   procedure Update_Title;
   procedure Save_Selected (Files : Adi.OS.String_Array);
   procedure Save_Project (Save_As : Boolean := False);
   procedure Open_Selected (Files : Adi.OS.String_Array);
   procedure Execute_Console_Line (Line : String);
   procedure Request_Action (Action : Pending_Action);
   procedure Confirm_Result (Dialog : Widget_Handle; Index : Natural; Caption : String);
   procedure Close_Requested (Window : Window_Handle; Allow : in out Boolean);
   procedure Export_Selected (Files : Adi.OS.String_Array);
   procedure Reset_File_Menu;
   procedure Show_File_Menu (Button : Widget_Handle);
   procedure Menu_Selected (Menu : Menus.Menu_Handle; Index : Positive; Text : String);
end Editor_Project_Actions;
