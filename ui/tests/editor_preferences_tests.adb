with Ada.Command_Line;
with Adi.Core; use Adi.Core;
with Adi.Widget; use Adi.Widget;
with Adi.Window; use Adi.Window;
with Adi.SDL.Video;
with Interfaces.C;
with Editor_Application;
with Editor_Context; use Editor_Context;
with Editor_Preferences;
with Editor_Split;

procedure Editor_Preferences_Tests is
   use type Editor_Split.Views.Handle;
   use type Interfaces.C.int;
   Mode : constant String := Ada.Command_Line.Argument (1);
begin
   Editor_Application.Initialize;
   declare
      Saved : constant Editor_Preferences.Layout_Settings := Editor_Preferences.Current;
      Files : Editor_Split.Views.Ref := Editor_Split.Views.Borrow (Workspace);
      Preview : Editor_Split.Views.Ref := Editor_Split.Views.Borrow (Main_Split);
      Width, Height : aliased Interfaces.C.int;
      Resized : Boolean;
   begin
      if Mode = "write" then
         pragma Assert (not Saved.Loaded, "First launch uses defaults");
         Files.Fraction := 0.44;
         Preview.Fraction := 0.60;
         Resized := Boolean (Adi.SDL.Video.SDL_SetWindowSize (Get_SDL_Window (W), 960, 650));
         pragma Assert (Resized);
         Handle_Resize (W, (960.0, 650.0));
      elsif Mode = "read" then
         pragma Assert (Saved.Loaded and Saved.Width = 960 and Saved.Height = 650);
         pragma Assert (abs (Files.Fraction - 0.44) < 0.001 and
                        abs (Preview.Fraction - 0.60) < 0.001,
                        "Both panel proportions survive a new process");
         Resized := Boolean (Adi.SDL.Video.SDL_GetWindowSize
           (Get_SDL_Window (W), Width'Access, Height'Access));
         pragma Assert (Resized and then Width = 960 and then Height = 650,
                        "Restored dimensions reach the native window");
      elsif Mode = "defaults" then
         pragma Assert (not Saved.Loaded);
         pragma Assert (abs (Files.Fraction - 0.31) < 0.001 and
                        abs (Preview.Fraction - 0.70) < 0.001,
                        "Missing or invalid preferences use safe defaults");
      elsif Mode = "maximized" then
         pragma Assert (Saved.Loaded and then Saved.Maximized,
                        "Stored maximized state is loaded");
      else
         raise Program_Error with "Unknown test mode";
      end if;
      pragma Assert (FS.History_Length (Editor) = 0 and then not Dirty,
                     "Layout preferences never edit the project");
   end;
   --  Reproduce App.Run's close order: the native window is already gone by
   --  Shutdown. The cached values must still be saved successfully.
   Editor_Preferences.Capture (W);
   Destroy (W);
   Editor_Application.Shutdown;
end Editor_Preferences_Tests;
