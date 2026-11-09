with Ada.Text_IO;
with Ada.Unchecked_Deallocation;
with Framewise.Shell;
with Framewise.Decode;

package body Framewise.Session is

   use Framewise.Timeline;

   procedure Set (R : out Response; Ok : Boolean; Msg : String) renames Responses.Set;
   procedure Append (R : in out Response; Msg : String) renames Responses.Append;
   procedure Apply (S : in out Session; C : Command; R : out Response);
   procedure Replay (S : in out Session);
   procedure Do_List (S : Session; R : out Response);
   procedure Do_Info (S : Session; N : Name; R : out Response);
   procedure Do_Plan (S : Session; Output : String; R : out Response; Run : Boolean);
   procedure Do_Proxy (S : Session; N : Name; R : out Response);
   procedure Do_Save (S : Session; File : String; R : out Response);
   procedure Do_Load (S : in out Session; File : String; R : out Response);

   function To_TL (K : Commands.Media_Kind) return Timeline.Media_Kind is
     (case K is when Commands.Video => Timeline.Video,
                when Commands.Audio => Timeline.Audio,
                when Commands.Both  => Timeline.Both);

   -----------
   -- Apply --
   -----------

   procedure Apply (S : in out Session; C : Command; R : out Response) is
      Ok : Boolean := False;
   begin
      case C.K is
                  when Import =>
            if C.Length = 0 then
               declare
                  Length     : Duration_T;
                  Has_Video  : Boolean;
                  Has_Audio  : Boolean;
                  Probe_Ok   : Boolean;
                  Media      : Timeline.Media_Kind;
                  Proxy_File : constant String :=
                    Image (C.File) & ".proxy.mov";
               begin
                  Framewise.Decode.Probe
                    (Proxy_File,
                     Length,
                     Has_Video,
                     Has_Audio,
                     Probe_Ok);

                  if not Probe_Ok then
                     Set
                       (R,
                        False,
                        "err cannot probe " & Proxy_File);
                     return;
                  end if;

                  if Has_Video and Has_Audio then
                     Media := Timeline.Both;
                  elsif Has_Video then
                     Media := Timeline.Video;
                  elsif Has_Audio then
                     Media := Timeline.Audio;
                  else
                     Set
                       (R,
                        False,
                        "err proxy has no supported media tracks");
                     return;
                  end if;

                  Add_Source
                    (S.Seq,
                     C.Src_Name,
                     C.File,
                     Length,
                     Media,
                     Ok);
               end;
            else
               Add_Source
                 (S.Seq,
                  C.Src_Name,
                  C.File,
                  C.Length,
                  To_TL (C.Src_Kind),
                  Ok);
            end if;

            if not Ok then
               Set
                 (R,
                  False,
                  "err source exists or table full");
               return;
            end if;
         when Commands.Track =>
            Add_Track (S.Seq, C.Trk_Name, To_TL (C.Trk_Kind), Ok);
            if not Ok then
               Set (R, False, "err track exists or table full"); return;
            end if;
         when Place =>
            Place (S.Seq, C.Clip_Name, C.On, C.From, C.Src_In, C.Src_Out, C.Start, Ok);
            if not Ok then
               Set (R, False, "err cannot place: unknown track/source, bad window, or overlap");
               return;
            end if;
         when Move =>
            Move (S.Seq, C.Mv_Name, C.To, Ok);
            if not Ok then
               Set (R, False, "err cannot move: unknown clip or overlap"); return;
            end if;
         when Trim =>
            Trim (S.Seq, C.Tr_Name, C.New_In, C.New_Out, Ok);
            if not Ok then
               Set (R, False, "err cannot trim: unknown clip, bad window, or overlap"); return;
            end if;
         when Split =>
            Split (S.Seq, C.Sp_Name, C.Cut, C.Right, Ok);
            if not Ok then
               Set (R, False, "err cannot split: unknown clip, cut outside it, or name taken");
               return;
            end if;
         when Delete =>
            Delete (S.Seq, C.Target, Ok);
            if not Ok then
               Set (R, False, "err no clip named " & Image (C.Target)); return;
            end if;
         when Settings =>
            S.Cfg := (Width => C.Width, Height => C.Height, FPS => C.FPS,
                      Sample_Rate => S.Cfg.Sample_Rate);
         when others =>
            Set (R, False, "err not a modeling command"); return;
      end case;
      Set (R, True, "ok");
   end Apply;

   ------------
   -- Replay --
   ------------

   procedure Replay (S : in out Session) is
      R : Response;
   begin
      Clear (S.Seq);
      S.Cfg := Plan.Default_Settings;
      for I in 1 .. S.Count loop
         Apply (S, S.History (I), R);
      end loop;
   end Replay;

   -------------
   -- Queries --
   -------------

   procedure Do_List (S : Session; R : out Response) is
   begin
      Set (R, True, "ok sources:");
      for I in S.Seq.Sources'Range loop
         if S.Seq.Sources (I).Used then
            Append (R, " " & Image (S.Seq.Sources (I).N));
         end if;
      end loop;
      Append (R, " tracks:");
      for T in S.Seq.Tracks'Range loop
         if S.Seq.Tracks (T).Used then
            Append (R, " " & Image (S.Seq.Tracks (T).N) & "(");
            for I in 1 .. S.Seq.Tracks (T).Count loop
               Append (R, (if I > 1 then " " else "") & Image (S.Seq.Tracks (T).Clips (I).N));
            end loop;
            Append (R, ")");
         end if;
      end loop;
      Append (R, " end " & Image_Time (Sequence_End (S.Seq)));
   end Do_List;

   procedure Do_Info (S : Session; N : Name; R : out Response) is
      T  : Track_Id;
      I  : Clip_Index;
      Sr : constant Source_Id := Find_Source (S.Seq, N);
      Tr : constant Track_Id := Find_Track (S.Seq, N);
   begin
      Find_Clip (S.Seq, N, T, I);
      if T /= 0 then
         declare
            C : Clip renames S.Seq.Tracks (T).Clips (I);
         begin
            Set (R, True, "ok clip " & Image (N) & " on " & Image (S.Seq.Tracks (T).N)
                 & " from " & Image (S.Seq.Sources (C.Src).N)
                 & " in " & Image_Time (C.Src_In) & " out " & Image_Time (C.Src_Out)
                 & " at " & Image_Time (C.Start) & " ends " & Image_Time (Ends (C))
                 & " length " & Image_Time (Length (C)));
         end;
      elsif Sr /= No_Source then
         Set (R, True, "ok source " & Image (N) & " file " & Image (S.Seq.Sources (Sr).File)
              & " length " & Image_Time (S.Seq.Sources (Sr).Length));
      elsif Tr /= 0 then
         Set (R, True, "ok track " & Image (N) & " clips" & S.Seq.Tracks (Tr).Count'Image
              & " end " & Image_Time (Track_End (S.Seq, Tr)));
      else
         Set (R, False, "err nothing named " & Image (N));
      end if;
   end Do_Info;

   procedure Do_Plan (S : Session; Output : String; R : out Response; Run : Boolean) is
      Text : String (1 .. Plan.Max_Plan);
      Last : Natural;
      Ok   : Boolean;
   begin
      Plan.Generate (S.Seq, S.Cfg, Output, Text, Last, Ok);
      if not Ok then
         Set (R, False, "err nothing to render (no video track with clips) or plan too long");
         return;
      end if;
      if not Run then
         Set (R, True, "ok " & Text (1 .. Last));
         return;
      end if;
      declare
         Status : Integer;
         Found  : Boolean;
      begin
         Shell.Run (Text (1 .. Last), Status, Found);
         if not Found then
            Set (R, False, "err no shell to run ffmpeg; use 'plan' and run it yourself");
         elsif Status = 0 then
            Set (R, True, "ok exported " & Output);
         else
            Set (R, False, "err ffmpeg exit" & Status'Image & "; run 'plan' to see the command");
         end if;
      end;
   end Do_Plan;

   --  The proxy is the file the editor actually reads: intra-only video
   --  (every frame a keyframe) and PCM audio, both decodable in pure Ada
   --  by Framewise.Decode. The original is only touched by export.
   function Proxy_Command (Source : String) return String is
     ("ffmpeg -y -hide_banner -loglevel error -i " & Shell.Quote_Path (Source)
      & " -vf scale=-2:540 -c:v mjpeg -q:v 3 -pix_fmt yuvj420p"
      & " -c:a pcm_s16le -ar 48000 -movflags +faststart "
      & Shell.Quote_Path (Source & ".proxy.mov"));

   procedure Do_Proxy (S : Session; N : Name; R : out Response) is
      Sr     : constant Source_Id := Find_Source (S.Seq, N);
      Status : Integer;
      Found  : Boolean;
   begin
      if Sr = No_Source then
         Set (R, False, "err no source named " & Image (N));
         return;
      end if;
      declare
         File : constant String := Image (S.Seq.Sources (Sr).File);
      begin
         Shell.Run (Proxy_Command (File), Status, Found);
         if not Found then
            Set (R, False, "err no shell to run ffmpeg: " & Proxy_Command (File));
         elsif Status = 0 then
            Set (R, True, "ok wrote " & File & ".proxy.mov");
         else
            Set (R, False, "err ffmpeg exit" & Status'Image & ": " & Proxy_Command (File));
         end if;
      end;
   end Do_Proxy;

   procedure Do_Save (S : Session; File : String; R : out Response) is
      use Ada.Text_IO;
      F : File_Type;
   begin
      Create (F, Out_File, File);
      Put_Line (F, "# framewise document, one command per line");
      for I in 1 .. S.Count loop
         Put_Line (F, Image (S.History (I)));
      end loop;
      Close (F);
      Set (R, True, "ok saved" & S.Count'Image & " commands to " & File);
   exception
      when others =>
         Set (R, False, "err cannot write " & File);
   end Do_Save;

   procedure Do_Load (S : in out Session; File : String; R : out Response) is
      use Ada.Text_IO;
      F : File_Type;
      Line_No : Natural := 0;
   begin
      Open (F, In_File, File);
      Clear (S.Seq);
      S.Cfg := Plan.Default_Settings;
      S.Count := 0;
      while not End_Of_File (F) loop
         declare
            Line : constant String := Get_Line (F);
            RL   : Response;
         begin
            Line_No := Line_No + 1;
            Execute (S, Line, RL);
            if not RL.Ok then
               Close (F);
               Set (R, False, "err line" & Line_No'Image & ": " & Image (RL));
               return;
            end if;
         end;
      end loop;
      Close (F);
      Set (R, True, "ok loaded" & S.Count'Image & " commands from " & File);
   exception
      when others =>
         Set (R, False, "err cannot read " & File);
   end Do_Load;

   -------------
   -- Execute --
   -------------

   procedure Execute (S : in out Session; Line : String; R : out Response) is
      C    : Command;
      Ok   : Boolean;
      Err  : Error_String;
      Last : Natural;
   begin
      if Line'Length > Max_Line then
         Set (R, False, "err line too long");
         return;
      end if;
      Parse (Line, C, Ok, Err, Last);
      if not Ok then
         Set (R, False, "err " & Err (1 .. Last));
         return;
      end if;
      case C.K is
         when Modeling =>
            if S.Count >= Max_History then
               Set (R, False, "err history full");
               return;
            end if;
            Apply (S, C, R);
            if R.Ok then
               S.Count := S.Count + 1;
               S.History (S.Count) := C;
            end if;
         when Undo =>
            if S.Count = 0 then
               Set (R, False, "err nothing to undo");
            else
               S.Count := S.Count - 1;
               Replay (S);
               Set (R, True, "ok undid; history" & S.Count'Image);
            end if;
         when List => Do_List (S, R);
         when Info   => Do_Info (S, C.Target, R);
         when Commands.Plan => Do_Plan (S, Image (C.Out_File), R, Run => False);
         when Export => Do_Plan (S, Image (C.Out_File), R, Run => True);
         when Proxy  => Do_Proxy (S, C.Target, R);
         when Save   => Do_Save (S, Image (C.Out_File), R);
         when Load   => Do_Load (S, Image (C.Out_File), R);
         when Comment | Empty => Set (R, True, "ok");
      end case;
   end Execute;

   protected body Export_Completion is
      procedure Finish (Success : Boolean) is
      begin
         Ok := Success;
      end Finish;

      function Succeeded return Boolean is (Ok);
   end Export_Completion;

   task body Export_Waiter is
      use type GNAT.OS_Lib.Process_Id;
      Expected, PID : GNAT.OS_Lib.Process_Id;
      Success : Boolean;
   begin
      accept Await (PID : GNAT.OS_Lib.Process_Id) do
         Expected := PID;
      end Await;
      --  Only wait here. Process creation remains on the caller thread and
      --  all UI updates remain on the UI thread. Windows GNAT supports this
      --  blocking wait, but its Non_Blocking_Wait_Process always returns no PID.
      loop
         GNAT.OS_Lib.Wait_Process (PID, Success);
         exit when PID = Expected or else PID = GNAT.OS_Lib.Invalid_Pid;
      end loop;
      Result.Finish (PID = Expected and then Success);
   exception
      when others => Result.Finish (False);
   end Export_Waiter;

   procedure Free_Waiter is new Ada.Unchecked_Deallocation
     (Export_Waiter, Export_Waiter_Access);
   procedure Free_Completion is new Ada.Unchecked_Deallocation
     (Export_Completion, Export_Completion_Access);

   function Export_Running (Job : Export_Job) return Boolean is
      use type GNAT.OS_Lib.Process_Id;
   begin
      return Job.PID /= GNAT.OS_Lib.Invalid_Pid;
   end Export_Running;

   function Export_Output (Line : String) return String is
      C : Command;
      Ok : Boolean;
      Err : Error_String;
      Last : Natural;
   begin
      if Line'Length > Max_Line then
         return "";
      end if;
      Parse (Line, C, Ok, Err, Last);
      return (if Ok and then C.K = Export then Image (C.Out_File) else "");
   end Export_Output;

   procedure Start_Export
     (S : Session; Output : String; Job : in out Export_Job; R : out Response;
      Wait_In_Background : Boolean := False)
   is
      use GNAT.OS_Lib;
      Text : String (1 .. Plan.Max_Plan);
      Last : Natural;
      Ok : Boolean;
      FD : File_Descriptor;
   begin
      if Export_Running (Job) then
         Set (R, False, "err an export is already running");
         return;
      end if;
      if Output'Length not in 1 .. Max_Path then
         Set (R, False, "err invalid output path");
         return;
      end if;
      Plan.Generate (S.Seq, S.Cfg, Output, Text, Last, Ok);
      if not Ok then
         Set (R, False, "err nothing to render or export plan too long");
         return;
      end if;
      Create_Temp_File (FD, Job.Log_File);
      if FD = Invalid_FD then
         Free (Job.Log_File);
         Set (R, False, "err cannot create export diagnostics file");
         return;
      end if;
      Job.PID := Shell.Start (Text (1 .. Last), FD);
      Close (FD);
      if not Export_Running (Job) then
         Delete_File (Job.Log_File.all, Ok);
         Free (Job.Log_File);
         Set (R, False, "err cannot start native shell for FFmpeg");
         return;
      end if;
      if Wait_In_Background or else Shell.Is_Windows then
         Job.Completion := new Export_Completion;
         Job.Waiter := new Export_Waiter (Job.Completion);
         Job.Waiter.Await (Job.PID);
      end if;
      Job.Output := To_Path (Output);
      Set (R, True, "ok exporting " & Output);
   end Start_Export;

   procedure Poll_Export (Job : in out Export_Job; R : out Response; Done : out Boolean) is
      use GNAT.OS_Lib;
      PID : Process_Id;
      Success, Deleted : Boolean;
      F : Ada.Text_IO.File_Type;
   begin
      Done := False;
      Set (R, True, "ok waiting for export");
      if not Export_Running (Job) then
         return;
      end if;
      if Job.Waiter /= null then
         --  Read only after task termination, then release both objects. A
         --  completed export can be followed by another export in the same job.
         if not Job.Waiter.all'Terminated then
            return;
         end if;
         Success := Job.Completion.Succeeded;
         PID := Job.PID;
         Free_Waiter (Job.Waiter);
         Free_Completion (Job.Completion);
      else
         Non_Blocking_Wait_Process (PID, Success);
      end if;
      if PID /= Job.PID then
         return;
      end if;
      Job.PID := Invalid_Pid;
      Done := True;
      Set (R, Success, (if Success then "ok exported " else "err FFmpeg export failed: ") &
        Image (Job.Output));
      if not Success then
         begin
            Ada.Text_IO.Open (F, Ada.Text_IO.In_File, Job.Log_File.all);
            while not Ada.Text_IO.End_Of_File (F) loop
               Append (R, ASCII.LF & Ada.Text_IO.Get_Line (F));
            end loop;
            Ada.Text_IO.Close (F);
         exception
            when Ada.Text_IO.Name_Error | Ada.Text_IO.Use_Error =>
               if Ada.Text_IO.Is_Open (F) then
                  Ada.Text_IO.Close (F);
               end if;
               Append (R, ASCII.LF & "Cannot read FFmpeg diagnostics.");
         end;
      end if;
      Delete_File (Job.Log_File.all, Deleted);
      Free (Job.Log_File);
   end Poll_Export;

   function Sequence_Of (S : Session) return Timeline.Sequence is (S.Seq);
   function Settings_Of (S : Session) return Plan.Settings is (S.Cfg);
   function History_Length (S : Session) return Natural is (S.Count);
   function History_Line (S : Session; I : Positive) return String is
     (Image (S.History (I)));

end Framewise.Session;
