using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Data;
using System.Drawing;
using System.Linq;
using System.Net;
using System.Text;
using System.Threading.Tasks;
using System.Windows.Forms;

namespace WindowsFormsApp1
{
    public partial class Form1 : Form
    {
        public Form1()
        {
            InitializeComponent();
        }

        private void PictureBox1_Click(object sender, EventArgs e)
        {

        }

        private void Form1_Load(object sender, EventArgs e)
        {
            Image pic =  Image.FromStream(WebRequest.Create("https://lud4.cn/LINSHI/HTML53D/imgs/3.jpg").GetResponse().GetResponseStream());

            this.pictureBox1.Image = pic;
            this.pictureBox1.Height =  pic.Height;
            this.pictureBox1.Width = pic.Width;
        
        }

        private void Form1_BackgroundImageChanged(object sender, EventArgs e)
        {

        }
    }
}
