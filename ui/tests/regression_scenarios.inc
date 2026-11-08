      --  Test-only replacement for A.Run. Runs against the real editor,
      --  callback procedures, widgets and SDL window created above.
      declare
         Test_Dir : constant String := Ada.Environment_Variables.Value ("FRAMEWISE_TEST_DIR");
         Initial_History : US.Unbounded_String;
         Clip_Name : US.Unbounded_String;
         function Native_Title (Window : Adi.SDL.Video.SDL_Window_Ptr)
           return Interfaces.C.Strings.chars_ptr
           with Import, Convention => C, External_Name => "SDL_GetWindowTitle";

         procedure Check (Condition : Boolean; Message : String) is
         begin
            if not Condition then
               raise Program_Error with Message;
            end if;
         end Check;

         procedure Stage (Name : String) is
         begin
            Ada.Text_IO.Put_Line ("CHECK: " & Name);
         end Stage;

         function Files (Path : String) return Adi.OS.String_Array is
           ([US.To_Unbounded_String (Path)]);

         procedure Apply is
         begin
            Form_Result (Null_Handle, 1, "Apply");
         end Apply;

         procedure Assert_Centered is
            L : constant Rectangle := Get_Geometry (+Start_Button);
            R : constant Rectangle := Get_Geometry (+End_Button);
            P : constant Rectangle := Get_Geometry (+Preview);
         begin
            Check (abs ((L.X + R.X + R.Width) / 2.0 - (P.X + P.Width / 2.0)) < 1.0,
                   "Playback controls must remain centered under preview");
         end Assert_Centered;
      begin
         Stage ("startup, playback layout and timeline selector order");
         Render (W);
         Check (Interfaces.C.Strings.Value (Native_Title (Get_SDL_Window (W))) = "Framewise",
                "Untitled window title");
         Check (Current_Filter = All_Media, "All must be the default filter");
         Check (Has_State (+Filter_Buttons (All_Media), State_Selected), "All filter highlight");
         Check (Has_State (+Play_Button, State_Disabled), "Playback must remain unavailable");
         Check (Get_Child_Handle (+Placement_Row, 2) = Widget_Handle'(+Source_Choice),
                "Media selector must precede target track");
         Check (Get_Child_Handle (+Placement_Row, 4) = Widget_Handle'(+Track_Choice),
                "Track selector order");
         Check (Get_Child_Handle (+Placement_Row, 5) = Widget_Handle'(+Place_Button),
                "Place button order");
         Assert_Centered;
         Check (Get_Scroll_Max_Offset_Y (+Track_Scroll) = 0.0, "Empty timeline must not overflow");

         Stage ("import callback, filters and canceled import");
         Import_Selected (Files (Test_Dir & "/video.mp4"));
         Check (Dialogs.Is_Shown (Form), "Import should request duration");
         Inputs.Set_Text (Values (2), "3");
         Apply;
         Check (Reply.Ok, "Video import should succeed");
         Execute_Line ("import music " & Test_Dir & "/audio.wav 3 audio");
         Check (Reply.Ok, "Audio registration");
         Execute_Line ("import combined " & Test_Dir & "/both.mp4 3 both");
         Check (Reply.Ok, "Combined media registration");
         Initial_History := History;
         Check (Combos.Option_Count (Source_Choice) = 3, "All filter source count");
         Clicked (+Filter_Buttons (Video_Media));
         Check (Combos.Option_Count (Source_Choice) = 2, "Video includes combined media");
         Check (Ada.Strings.Fixed.Index (Adi.Widget.Text_Editor.Get_Text (Sources), "music") = 0,
                "Audio-only sources hidden by Video");
         Clicked (+Filter_Buttons (Audio_Media));
         Check (Combos.Option_Count (Source_Choice) = 2, "Audio includes combined media");
         Check (Has_State (+Filter_Buttons (Audio_Media), State_Selected), "Active filter highlight");
         Clicked (+Filter_Buttons (All_Media));
         Import_Selected (Adi.OS.Empty_Strings);
         Check (History = Initial_History, "Filtering/canceling import must not edit the document");

         Stage ("named tracks, dialog width, caret and invalid names");
         Clicked (+Add_Track_Button);
         Render (W);
         Check (Field (1)'Length > 0, "Generated track name default");
         Check (Get_Focus_Handle (W) = Widget_Handle'(+Values (1)), "Track name initial focus");
         Check (Get_Geometry (+Values (1)).Width = Get_Geometry (+Kind_Choice).Width,
                "Track name and media kind must have equal widths");
         declare
            Caret_Visible : Boolean := False;
         begin
            for I in 1 .. Item_Count (+Values (1)) loop
               declare
                  Drawn : constant Item := Get_Item (+Values (1), I);
               begin
                  Caret_Visible := Caret_Visible or else
                    (Drawn.Part = Cursor_Part and then Drawn.Geometry.Width > 0.0
                     and then Drawn.Geometry.Height > 0.0);
               end;
            end loop;
            Check (Caret_Visible, "Focused name field must draw a caret");
         end;
         Inputs.Set_Text (Values (1), "Main_Video");
         Apply;
         Check (Reply.Ok and then not Dialogs.Is_Shown (Form), "Named track creation");
         Check (Framewise.Image (FS.Sequence_Of (Editor).Tracks (1).N) = "Main_Video",
                "Entered track name must reach the model");
         Initial_History := History;
         Clicked (+Add_Track_Button);
         Inputs.Set_Text (Values (1), "Main_Video");
         Apply;
         Check (not Reply.Ok and then Dialogs.Is_Shown (Form), "Duplicate name rejected");
         Inputs.Set_Text (Values (1), "Bad Name");
         Apply;
         Check (History = Initial_History, "Invalid names must not edit the document");
         Inputs.Set_Text (Values (1), "");
         Apply;
         Check (History = Initial_History, "Empty name rejected");
         Inputs.Set_Text (Values (1), "abcdefghijklmnopqrstuvwxyz1234567");
         Apply;
         Check (History = Initial_History, "Overlong name rejected");
         Form_Result (Null_Handle, 2, "Cancel");

         Stage ("clip placement, numeric move, rejected overlap and undo");
         Combos.Set_Selected_Index (Source_Choice, 1);
         Combos.Set_Selected_Index (Track_Choice, 1);
         Clicked (+Place_Button);
         Clip_Name := Form_Target;
         Inputs.Set_Text (Values (1), "0");
         Inputs.Set_Text (Values (2), "2");
         Inputs.Set_Text (Values (3), "0");
         Apply;
         Check (Reply.Ok, "Place selected media");
         declare
            T : Timeline_View.Views.Ref := Timeline_View.Views.Borrow (Tracks);
         begin
            T.Selected_Clip := Clip_Name;
         end;
         Clicked (+Move_Button);
         Inputs.Set_Text (Values (1), "0.5");
         Apply;
         Check (Reply.Ok, "Numeric move");
         Check (FS.Sequence_Of (Editor).Tracks (1).Clips (1).Start = Framewise.Timebase / 2,
                "Move start applied");
         Clicked (+Undo_Button);
         Check (FS.Sequence_Of (Editor).Tracks (1).Clips (1).Start = 0, "Undo move");
         Initial_History := History;
         Clicked (+Place_Button);
         Inputs.Set_Text (Values (1), "0");
         Inputs.Set_Text (Values (2), "2");
         Inputs.Set_Text (Values (3), "1");
         Apply;
         Check (not Reply.Ok and then Dialogs.Is_Shown (Form), "Overlap must be rejected");
         Check (History = Initial_History, "Rejected placement must not edit history");
         Form_Result (Null_Handle, 2, "Cancel");

         Stage ("Razor selected state and transport navigation");
         Clicked (+Razor_Button);
         Check (Has_State (+Razor_Button, State_Selected), "Razor active highlight");
         Clicked (+Razor_Button);
         Check (not Has_State (+Razor_Button, State_Selected), "Razor inactive highlight");
         Clicked (+End_Button);
         declare
            T : Timeline_View.Views.Ref := Timeline_View.Views.Borrow (Tracks);
         begin
            Check (T.Playhead = 2 * Framewise.Timebase, "Go to project end");
         end;
         Clicked (+Start_Button);
         declare
            T : Timeline_View.Views.Ref := Timeline_View.Views.Borrow (Tracks);
         begin
            Check (T.Playhead = 0, "Go to beginning");
         end;
         Check (History = Initial_History, "Tool and transport controls must not edit history");

         Stage ("settings and real export callback");
         Menu_Selected (File_Menu, 6, "Project Settings");
         Inputs.Set_Text (Values (1), "320");
         Inputs.Set_Text (Values (2), "180");
         Inputs.Set_Text (Values (3), "24");
         Apply;
         Check (Reply.Ok and then FS.Settings_Of (Editor).Width = 320, "Settings dialog");
         Export_Selected (Files (Test_Dir & "/export.mp4"));
         Check (Reply.Ok and then Ada.Directories.Exists (Test_Dir & "/export.mp4"), "Real GUI export");
         Initial_History := History;
         Export_Selected (Files (Test_Dir & "/missing/export.mp4"));
         Check (not Reply.Ok, "Failed export must report failure");
         Export_Selected (Adi.OS.Empty_Strings);
         Check (History = Initial_History, "Export/failure/cancel must not edit project");

         Stage ("save, save-as, cancel, dirty state and reopen");
         Save_Selected (Files (Test_Dir & "/first"));
         Check (US.To_String (Project_Path) = Test_Dir & "/first.fw", "First save adds extension");
         Check (not Dirty, "Successful save clears dirty state");
         Save_Selected (Adi.OS.Empty_Strings);
         Check (US.To_String (Project_Path) = Test_Dir & "/first.fw", "Canceled save keeps path");
         Execute_Line ("track Extra audio");
         Check (Dirty, "Editing marks project dirty");
         Request_Action (New_Project);
         Check (Dialogs.Is_Shown (Confirm), "New must protect unsaved edits");
         Confirm_Result (Null_Handle, 2, "Cancel");
         Dialogs.Hide (Confirm);
         Check (Dirty and then FS.Sequence_Of (Editor).Tracks (2).Used, "Cancel retains project");
         Request_Action (Open_Project);
         Check (Dialogs.Is_Shown (Confirm), "Open must protect unsaved edits");
         Confirm_Result (Null_Handle, 2, "Cancel");
         Dialogs.Hide (Confirm);
         Check (Dirty, "Cancel open keeps unsaved edits");
         declare
            Allowed : Boolean := True;
         begin
            Close_Requested (W, Allowed);
            Check (not Allowed and then Dialogs.Is_Shown (Confirm), "Close protects unsaved project");
            Confirm_Result (Null_Handle, 2, "Cancel");
            Dialogs.Hide (Confirm);
         end;
         Save_Project;
         Check (not Dirty, "Save writes to current path");
         Save_Selected (Files (Test_Dir & "/gui.fw"));
         Check (US.To_String (Project_Path) = Test_Dir & "/gui.fw", "Save As changes active path");
         Check (Interfaces.C.Strings.Value (Native_Title (Get_SDL_Window (W))) = "Framewise gui",
                "Save As updates native window title");
         Execute_Line ("track Temporary audio");
         Clicked (+Undo_Button);
         Check (not Dirty, "Undo to saved state clears dirty flag");
         Execute_Line ("track Gui_Only audio");
         Save_Project;
         Check (not Dirty, "Save after Save As uses new current document");
         Request_Action (New_Project);
         Check (FS.History_Length (Editor) = 0 and then US.Length (Project_Path) = 0, "New clears project");
         Open_Selected (Files (Test_Dir & "/first.fw"));
         Check (Reply.Ok and then FS.Sequence_Of (Editor).Tracks (2).Used, "Save persisted later edit");
         Check (not FS.Sequence_Of (Editor).Tracks (3).Used, "Save As must preserve original document");
         Check (Interfaces.C.Strings.Value (Native_Title (Get_SDL_Window (W))) = "Framewise first",
                "Open updates native window title");
         Open_Selected (Files (Test_Dir & "/gui.fw"));
         Check (Reply.Ok and then not Dirty, "Reopen saved project");
         Check (Framewise.Image (FS.Sequence_Of (Editor).Tracks (3).N) = "Gui_Only",
                "Save after Save As persisted only in the new file");
         Initial_History := History;
         Open_Selected (Adi.OS.Empty_Strings);
         Check (History = Initial_History, "Cancel open retains project");

         Stage ("resizing dividers through window event routing");
         Render (W);
         declare
            G : constant Rectangle := Get_Geometry (+Workspace);
            Before : constant Pixel_Type := G.Height;
         begin
            Adi.Window.On_Mouse_Down (W, G.X + 20.0, G.Y + G.Height + 4.0, Left_Button);
            Adi.Window.On_Mouse_Move (W, G.X + 20.0, G.Y + G.Height - 60.0);
            Adi.Window.On_Mouse_Up (W, G.X + 20.0, G.Y + G.Height - 60.0, Left_Button);
            Render (W);
            Check (Get_Geometry (+Workspace).Height < Before, "Horizontal divider must drag");
         end;
         declare
            G : constant Rectangle := Get_Geometry (+Bin);
         begin
            Adi.Window.On_Mouse_Down (W, G.X + G.Width + 4.0, G.Y + 20.0, Left_Button);
            Adi.Window.On_Mouse_Move (W, G.X + G.Width + 50.0, G.Y + 20.0);
            Adi.Window.On_Mouse_Up (W, G.X + G.Width + 50.0, G.Y + 20.0, Left_Button);
            Render (W);
            Check (Get_Geometry (+Bin).Width > G.Width, "Vertical divider must drag");
         end;
         Assert_Centered;
         Check (History = Initial_History, "Resizing must not edit document");

         Stage ("scrollbar routed drag and track click must not edit clips");
         Open_Selected (Files ("examples/cut.fw"));
         Check (Reply.Ok, "Open bundled example");
         for I in 1 .. 6 loop
            Execute_Line ("track overflow" & Ada.Strings.Fixed.Trim (I'Image, Ada.Strings.Both));
            Check (Reply.Ok, "Create overflowing tracks");
         end loop;
         Render (W);
         Initial_History := History;
         declare
            G : constant Rectangle := Get_Geometry (+Track_Scroll);
         begin
            Check (Get_Scroll_Max_Offset_Y (+Track_Scroll) > 0.0, "Tracks must overflow");
            Adi.Window.On_Mouse_Down (W, G.X + G.Width - 7.0, G.Y + 10.0, Left_Button);
            Adi.Window.On_Mouse_Move (W, G.X + G.Width - 7.0, G.Y + G.Height);
            Adi.Window.On_Mouse_Up (W, G.X + G.Width - 7.0, G.Y + G.Height, Left_Button);
            Check (Get_Scroll_Offset_Y (+Track_Scroll) > 0.0, "Scrollbar thumb must drag through window routing");
            Set_Scroll_Offset_Y (+Track_Scroll, 0.0);
            Render (W);
            Adi.Window.On_Mouse_Down (W, G.X + G.Width - 7.0, G.Y + G.Height - 10.0, Left_Button);
            Adi.Window.On_Mouse_Up (W, G.X + G.Width - 7.0, G.Y + G.Height - 10.0, Left_Button);
            Check (Get_Scroll_Offset_Y (+Track_Scroll) > 0.0, "Clicking scrollbar track must page");
            Check (History = Initial_History, "Scrollbar must not edit history");
            declare
               T : Timeline_View.Views.Ref := Timeline_View.Views.Borrow (Tracks);
            begin
               Check (not T.Drag_Active and then not T.Scrubbing, "Scrollbar must not start a clip gesture");
            end;
         end;
         Request_Action (New_Project);
         Check (Dialogs.Is_Shown (Confirm), "Dirty overflow project discard prompt");
         Confirm_Result (Null_Handle, 1, "Discard");
         Dialogs.Hide (Confirm);
         Render (W);
         Check (Get_Scroll_Max_Offset_Y (+Track_Scroll) = 0.0, "Empty timeline hides scrollbar");
         Check (Get_Scroll_Offset_Y (+Track_Scroll) = 0.0, "Old scroll offset cleared");
         Check (Current_Filter = All_Media, "New resets filter");
         Stage ("console opening, caret, routed typing and command execution");
         declare
            procedure Press_Enter is
            begin
               Adi.Window.On_Key_Down
                 (W, Adi.SDL.Events.SDL_SCANCODE_RETURN, 0, 0, False);
            end Press_Enter;

            procedure Click_Control (H : Widget_Handle) is
               G : constant Rectangle := Get_Geometry (H);
            begin
               Adi.Window.On_Mouse_Down (W, G.X + G.Width / 2.0, G.Y + G.Height / 2.0, Left_Button);
               Adi.Window.On_Mouse_Up (W, G.X + G.Width / 2.0, G.Y + G.Height / 2.0, Left_Button);
            end Click_Control;

            procedure Command (Line : String) is
            begin
               Adi.Window.On_Text_Input (W, Line);
               Press_Enter;
               Check (Inputs.Get_Text (Console_Input) = "", "Submitted input clears");
               Check (Get_Focus_Handle (W) = Widget_Handle'(+Console_Input), "Input retains focus");
            end Command;

            Caret_Visible : Boolean := False;
            Before : US.Unbounded_String;
         begin
            Check (Get_Geometry (+Console_Button).X > Get_Geometry (+File_Button).X + 500.0,
                   "Console button belongs at far right of top bar");
            Click_Control (+Console_Button);
            Render (W);
            Check (Dialogs.Is_Shown (Console_Dialog), "Console button opens floating dialog");
            Check (Overlay_Count (W) = 1, "Console appears above editor");
            Check (Get_Focus_Handle (W) = Widget_Handle'(+Console_Input), "Console opens ready to type");
            for I in 1 .. Item_Count (+Console_Input) loop
               declare
                  Drawn : constant Item := Get_Item (+Console_Input, I);
               begin
                  Caret_Visible := Caret_Visible or else
                    (Drawn.Part = Cursor_Part and then Drawn.Geometry.Width > 0.0
                     and then Drawn.Geometry.Height > 0.0);
               end;
            end loop;
            Check (Caret_Visible, "Empty console input must draw a visible caret");
            Before := History;
            Command ("   ");
            Check (History = Before, "Blank console command must not change project");
            Inputs.Set_Text (Console_Input, "");
            Adi.Window.On_Text_Input (W, "track consoleTrack video");
            Adi.Window.On_Key_Down (W, Adi.SDL.Events.SDL_SCANCODE_RETURN, 0, 0, True);
            Check (History = Before, "Repeated Enter must not execute a command");
            Press_Enter;
            Check (Reply.Ok and then Dirty, "Console edits the shared project");
            Check (Combos.Get_Selected_Text (Track_Choice) = "consoleTrack", "Console refreshes track dropdown");
            Check (Ada.Strings.Fixed.Index
              (Adi.Widget.Text_Editor.Get_Text (Console_Output), "> track consoleTrack video") > 0,
              "Transcript includes entered command");
            Before := History;
            Command ("list");
            Check (Reply.Ok and then History = Before, "Read-only commands retain project history");
            Command ("not_a_command");
            Check (not Reply.Ok and then History = Before, "Console reports rejected commands safely");
            Check (Ada.Strings.Fixed.Index
              (Adi.Widget.Text_Editor.Get_Text (Console_Output), "err ") > 0, "Transcript includes errors");
            Adi.Window.On_Key_Down
              (W, Adi.SDL.Events.SDL_SCANCODE_Z, 0, Adi.SDL.Events.SDL_KMOD_CTRL, False);
            Check (History = Before, "Console text shortcuts must not undo project edits");

            Inputs.Set_Text (Console_Input, "");
            Command ("save " & Test_Dir & "/console.fw");
            Check (Reply.Ok and then not Dirty, "Console save clears dirty state");
            Check (US.To_String (Project_Path) = Test_Dir & "/console.fw", "Console save updates project path");
            Command ("save " & Test_Dir & "/missing/console.fw");
            Check (not Reply.Ok and then not Dirty and then
              US.To_String (Project_Path) = Test_Dir & "/console.fw",
              "Failed console save must preserve current document bookkeeping");
            Command ("load " & Test_Dir & "/missing.fw");
            Check (not Reply.Ok and then not Dirty and then History = Before,
                   "Missing console load preserves project and saved state");
            Command ("track extra audio");
            Check (Reply.Ok and then Dirty, "Edit after save marks project dirty");
            Command ("load " & Test_Dir & "/console.fw");
            Check (Reply.Ok and then not Dirty and then History = Before, "Console load restores saved document");
            Check (Interfaces.C.Strings.Value (Native_Title (Get_SDL_Window (W))) = "Framewise console",
                   "Console load updates native title");
            Command ("undo");
            Check (Reply.Ok and then Dirty, "Console undo refreshes dirty state");
            Render (W);
            Before := US.To_Unbounded_String (Adi.Widget.Text_Editor.Get_Text (Console_Output));
            Click_Control (+Dialogs.Get_Button_Handle (Console_Dialog, 2));
            Check (not Dialogs.Is_Shown (Console_Dialog), "Close dismisses console");
            Check (Get_Focus_Handle (W) = Widget_Handle'(+Tracks), "Close returns focus to editor");
            Render (W);
            Click_Control (+Console_Button);
            Render (W);
            Check (US.To_Unbounded_String (Adi.Widget.Text_Editor.Get_Text (Console_Output)) = Before,
                   "Console transcript persists when reopened");
            Adi.Window.On_Text_Input (W, "list");
            Click_Control (+Dialogs.Get_Button_Handle (Console_Dialog, 1));
            Check (Reply.Ok and then Inputs.Get_Text (Console_Input) = "", "Run button submits input");
            Stage ("incomplete plan after opening cut.fw must not crash the console");
            Click_Control (+Dialogs.Get_Button_Handle (Console_Dialog, 2));
            Open_Selected (Files ("examples/cut.fw"));
            Check (Reply.Ok, "Open cut.fw through the project picker callback");
            Before := History;
            Render (W);
            Click_Control (+Console_Button);
            Render (W);
            Command ("plan");
            Check (not Reply.Ok and then History = Before and then not Dirty,
                   "Incomplete plan returns an error without changing the loaded project");
            Check (Ada.Strings.Fixed.Index
              (Adi.Widget.Text_Editor.Get_Text (Console_Output), "err bad arguments for plan") > 0,
              "Console transcript explains rejected plan");
            Command ("plan " & Test_Dir & "/planned.mp4");
            Check (Reply.Ok and then History = Before and then not Dirty,
                   "Console accepts a valid plan immediately after an incomplete command");
            Adi.Window.Handle_Resize (W, (960.0, 650.0));
            Render (W);
            declare
               G : constant Rectangle := Get_Geometry (+Console_Input);
            begin
               Check (G.Width > 0.0 and then G.Height > 0.0 and then
                 G.X >= 0.0 and then G.X + G.Width <= 960.0 and then
                 G.Y >= 0.0 and then G.Y + G.Height <= 650.0,
                 "Console input remains accessible in a smaller window");
            end;
            Adi.Window.On_Key_Down (W, Adi.SDL.Events.SDL_SCANCODE_ESCAPE, 0, 0, False);
            Check (not Dialogs.Is_Shown (Console_Dialog), "Escape dismisses console");
         end;
         Ada.Text_IO.Put_Line ("PASS: editor workflow regression scenarios");
      end;
