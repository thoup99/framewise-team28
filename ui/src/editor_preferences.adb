with Ada.Directories;
with Ada.Environment_Variables;
with Ada.Text_IO;
with Adi.Widget; use Adi.Widget;
with Adi.Window; use Adi.Window;
with Adi.SDL.Video;
with Interfaces.C;
with Editor_Context; use Editor_Context;
with Editor_Split;

package body Editor_Preferences is
   use type Editor_Split.Views.Handle;
   use type Interfaces.C.int;
   Cached : Layout_Settings;
   Version : constant String := "framewise-layout-v1";

   function Configuration_Path return String is
      function Env (Name : String) return String is
        (Ada.Environment_Variables.Value (Name, ""));
   begin
      if Env ("FRAMEWISE_CONFIG_HOME") /= "" then
         return Env ("FRAMEWISE_CONFIG_HOME") & "/layout.conf";
      elsif Env ("APPDATA") /= "" then
         return Env ("APPDATA") & "/Framewise/layout.conf";
      elsif Env ("XDG_CONFIG_HOME") /= "" then
         return Env ("XDG_CONFIG_HOME") & "/framewise/layout.conf";
      elsif Env ("HOME") /= "" then
         return Env ("HOME") & "/.config/framewise/layout.conf";
      else
         return "";
      end if;
   end Configuration_Path;

   function Current return Layout_Settings is (Cached);

   procedure Load is
      F : Ada.Text_IO.File_Type;
      Candidate : Layout_Settings;
   begin
      Cached := (others => <>);
      if Configuration_Path = "" then
         return;
      end if;
      Ada.Text_IO.Open (F, Ada.Text_IO.In_File, Configuration_Path);
      if Ada.Text_IO.Get_Line (F) /= Version then
         Ada.Text_IO.Close (F);
         return;
      end if;
      Candidate.Width := Positive'Value (Ada.Text_IO.Get_Line (F));
      Candidate.Height := Positive'Value (Ada.Text_IO.Get_Line (F));
      Candidate.Files_Fraction := Float'Value (Ada.Text_IO.Get_Line (F));
      Candidate.Preview_Fraction := Float'Value (Ada.Text_IO.Get_Line (F));
      Candidate.Maximized := Boolean'Value (Ada.Text_IO.Get_Line (F));
      Ada.Text_IO.Close (F);
      if Candidate.Width in 640 .. 16_384 and then Candidate.Height in 480 .. 16_384 and then
        Candidate.Files_Fraction in 0.05 .. 0.95 and then Candidate.Preview_Fraction in 0.05 .. 0.95
      then
         Candidate.Loaded := True;
         Cached := Candidate;
      end if;
   exception
      when Ada.Text_IO.Name_Error | Ada.Text_IO.Use_Error | Ada.Text_IO.End_Error |
           Ada.Text_IO.Data_Error | Ada.Text_IO.Device_Error | Constraint_Error =>
         if Ada.Text_IO.Is_Open (F) then
            Ada.Text_IO.Close (F);
         end if;
   end Load;

   procedure Apply_Panels is
      Files : Editor_Split.Views.Ref := Editor_Split.Views.Borrow (Workspace);
      Preview : Editor_Split.Views.Ref := Editor_Split.Views.Borrow (Main_Split);
   begin
      Files.Fraction := Cached.Files_Fraction;
      Preview.Fraction := Cached.Preview_Fraction;
      Mark_Dirty (+Workspace);
      Mark_Dirty (+Main_Split);
   end Apply_Panels;

   procedure Capture (Win : Window_Handle) is
      Width, Height : aliased Interfaces.C.int;
      Files : Editor_Split.Views.Ref := Editor_Split.Views.Borrow (Workspace);
      Preview : Editor_Split.Views.Ref := Editor_Split.Views.Borrow (Main_Split);
   begin
      if not Is_Valid (Win) then
         return;
      end if;
      --  Store native window coordinates rather than framebuffer pixels, so
      --  restoring on a HiDPI display does not multiply the dimensions again.
      if not Is_Minimized (Win) then
         Cached.Maximized := Is_Maximized (Win);
         if not Cached.Maximized and then not Is_Fullscreen (Win) and then
           Boolean (Adi.SDL.Video.SDL_GetWindowSize (Get_SDL_Window (Win), Width'Access, Height'Access))
         then
            if Width in 640 .. 16_384 and then Height in 480 .. 16_384 then
               Cached.Width := Positive (Width);
               Cached.Height := Positive (Height);
            end if;
         end if;
      end if;
      Cached.Files_Fraction := Float'Max (0.05, Float'Min (0.95, Files.Fraction));
      Cached.Preview_Fraction := Float'Max (0.05, Float'Min (0.95, Preview.Fraction));
   end Capture;

   procedure Save is
      F : Ada.Text_IO.File_Type;
      Path : constant String := Configuration_Path;
   begin
      if Path = "" then
         return;
      end if;
      Ada.Directories.Create_Path (Ada.Directories.Containing_Directory (Path));
      Ada.Text_IO.Create (F, Ada.Text_IO.Out_File, Path);
      Ada.Text_IO.Put_Line (F, Version);
      Ada.Text_IO.Put_Line (F, Cached.Width'Image);
      Ada.Text_IO.Put_Line (F, Cached.Height'Image);
      Ada.Text_IO.Put_Line (F, Cached.Files_Fraction'Image);
      Ada.Text_IO.Put_Line (F, Cached.Preview_Fraction'Image);
      Ada.Text_IO.Put_Line (F, Cached.Maximized'Image);
      Ada.Text_IO.Close (F);
   exception
      when Ada.Text_IO.Name_Error | Ada.Text_IO.Use_Error | Ada.Text_IO.Device_Error =>
         if Ada.Text_IO.Is_Open (F) then
            Ada.Text_IO.Close (F);
         end if;
   end Save;
end Editor_Preferences;
