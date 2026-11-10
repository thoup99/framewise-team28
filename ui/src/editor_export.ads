with Adi.Window;
with Editor_Console;
package Editor_Export is
   procedure Build;
   procedure Start (Path : String;
      Origin : Editor_Console.Command_Origin := Editor_Console.Editor_Action;
      Command : String := "");
   procedure Poll (Win : Adi.Window.Window_Handle);
   function Is_Busy return Boolean;
   function Is_Open return Boolean;
   function Details return String;
   function Progress_Percent return Natural;
   procedure Close;
end Editor_Export;
