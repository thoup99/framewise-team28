with Adi.CSS_Styles; use Adi.CSS_Styles;
with Timeline_View;
with Adi.Core; use Adi.Core;
with Adi.Widget; use Adi.Widget;
with Adi.Window; use Adi.Window;
with Adi.App;
with Adi.Layout_Util;
with Adi.SDL.Video;
with Interfaces.C.Extensions;
with Editor_Context; use Editor_Context;
with Editor_Layout;
with Editor_Preferences;
with Editor_Cursors;
with Editor_Controller;

package body Editor_Application is
   use type Timeline_View.Views.Handle;

   function Set_Window_Position
     (Window : Adi.SDL.Video.SDL_Window_Ptr; X, Y : Interfaces.C.int)
      return Interfaces.C.Extensions.bool
     with Import, Convention => C, External_Name => "SDL_SetWindowPosition";
   --  SDL_WINDOWPOS_CENTERED on the default display.
   Centered_Position : constant Interfaces.C.int := 16#2FFF0000#;

   procedure Initialize is
   begin
      A.Init;
      Adi.Layout_Util.Set_Px_Maps_To_Dip (True);
      A.Set_Target_FPS (60);

      Editor_Preferences.Load;
      declare
         Saved : constant Editor_Preferences.Layout_Settings := Editor_Preferences.Current;
         Bounds : aliased Adi.SDL.SDL_Rect;
         Size : Size_2D := (Pixel_Type (Saved.Width), Pixel_Type (Saved.Height));
      begin
         if Saved.Loaded then
            --  Keep the restored window reachable after changing monitors.
            if Adi.SDL.Video.SDL_GetDisplayUsableBounds
              (Adi.SDL.Video.SDL_GetPrimaryDisplay, Bounds'Access)
            then
               Size.Width := Pixel_Type'Min (Size.Width, Pixel_Type (Bounds.w));
               Size.Height := Pixel_Type'Min (Size.Height, Pixel_Type (Bounds.h));
            end if;
            W := Create_Window_Handle ("Framewise", Size, Maximized => Saved.Maximized);
         else
            W := Create_Window_Handle ("Framewise", Adi.Window.Extent (Px (1280.0), Px (850.0)));
         end if;
      end;
      declare
         Positioned : constant Interfaces.C.Extensions.bool := Set_Window_Position
           (Get_SDL_Window (W), Centered_Position, Centered_Position);
         pragma Unreferenced (Positioned);
      begin
         null;
      end;

      Editor_Layout.Build;
      Editor_Preferences.Apply_Panels;
      A.Add_Window (W);
      Editor_Controller.Refresh_Timeline;
      Set_Focus (W, +Tracks);
      Editor_Cursors.Connect;
      Connect_Frame (W, Editor_Preferences.Capture'Access);
   end Initialize;

   procedure Shutdown is
   begin
      --  App.Run destroys its window before returning. Capture caches every
      --  frame and close request, so saving still works after that destruction.
      if Is_Valid (W) then
         Editor_Preferences.Capture (W);
      end if;
      Editor_Preferences.Save;
      Editor_Cursors.Release;
      Menus.Destroy (Clip_Menu);
      Menus.Destroy (File_Menu);
      Adi.Window.Destroy (W);
   end Shutdown;

   procedure Run is
   begin
      Initialize;
      A.Run;
      Shutdown;
   end Run;
end Editor_Application;
