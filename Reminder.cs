using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Runtime.Serialization;
using System.Runtime.Serialization.Json;
using System.Threading;
using System.Windows.Forms;

namespace DesktopDDL
{
    [DataContract]
    public class Item
    {
        [DataMember] public string Id = Guid.NewGuid().ToString("N");
        [DataMember] public string Title = "";
        [DataMember] public string Requirements = "";
        [DataMember(EmitDefaultValue = false)] public string RequirementsRtf = "";
        [DataMember] public DateTime Due;
        [DataMember] public bool Done;
    }
    [DataContract]
    public class Config
    {
        [DataMember] public int VisibleCount = 5;
        [DataMember] public List<Item> Items = new List<Item>();
    }
    public static class Store
    {
        public static readonly string Folder = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "DesktopDDL");
        public static readonly string FileName = Path.Combine(Folder, "reminders.json");
        public static Config Data;
        public static string Warning;
        public static event EventHandler Changed;
        public static void NotifyChanged() { var handler = Changed; if (handler != null) handler(null, EventArgs.Empty); }
        public static void Load()
        {
            Data = new Config();
            if (!File.Exists(FileName)) return;
            try
            {
                using (var s = File.OpenRead(FileName)) Data = (Config)new DataContractJsonSerializer(typeof(Config)).ReadObject(s);
                if (Data == null) throw new InvalidDataException();
                if (Data.Items == null) Data.Items = new List<Item>();
                Data.Items = Data.Items.Where(x => x != null).ToList();
                foreach (var item in Data.Items)
                {
                    if (item.Requirements == null) item.Requirements = "";
                    if (item.RequirementsRtf == null) item.RequirementsRtf = "";
                }
                Data.VisibleCount = Math.Max(1, Math.Min(20, Data.VisibleCount));
            }
            catch (Exception ex)
            {
                var backup = FileName + ".broken-" + DateTime.Now.ToString("yyyyMMddHHmmss");
                File.Copy(FileName, backup, false);
                Data = new Config();
                Warning = "原数据无法读取，已备份到：\n" + backup + "\n\n" + ex.Message;
            }
        }
        public static bool Save()
        {
            try
            {
                Directory.CreateDirectory(Folder);
                string temp = FileName + ".tmp";
                using (var s = File.Create(temp)) new DataContractJsonSerializer(typeof(Config)).WriteObject(s, Data);
                if (File.Exists(FileName)) File.Replace(temp, FileName, FileName + ".bak");
                else File.Move(temp, FileName);
            }
            catch (Exception ex) { MessageBox.Show("保存失败，请检查磁盘与权限：\n" + ex.Message, "DDL 提醒栏"); return false; }
            NotifyChanged(); return true;
        }
        public static List<Item> Pending() { return Data.Items.Where(x => !x.Done).OrderBy(x => x.Due).ThenBy(x => x.Title).ToList(); }
    }
    static class Program
    {
        [STAThread]
        static void Main()
        {
            bool created;
            using (var mutex = new Mutex(true, "Local\\DesktopDDLReminder", out created))
            {
                if (!created) { MessageBox.Show("提醒栏已经运行。请查看右上角箭头或系统托盘。", "DDL 提醒栏"); return; }
                Native.SetProcessDPIAware();
                Application.EnableVisualStyles(); Application.SetCompatibleTextRenderingDefault(false);
                try
                {
                    Store.Load();
                    if (Store.Warning != null) MessageBox.Show(Store.Warning, "DDL 提醒栏");
                    Application.Run(new ReminderBar());
                }
                catch (Exception ex) { MessageBox.Show(ex.ToString(), "DDL 提醒栏启动失败"); }
            }
        }
    }
}
