# StranX Lead Management & WFM Portal - Deployment Guide

This repository contains the complete, production-ready source code for the Lead Management and WFM Tracking portal, built with Next.js (App Router), Supabase (PostgreSQL + Auth), and Tailwind CSS.

## 🚀 One-Click Deployment on Free Tiers

You can deploy this entirely for free without a credit card using Vercel (Frontend) and Supabase (Backend).

### Step 1: Create the Supabase Backend
1. Go to [Supabase](https://supabase.com/) and create a new project.
2. Once the project is provisioned, go to the **SQL Editor** in the left sidebar.
3. Open the `schema.sql` file located in the root of this repository.
4. Copy the entire contents of `schema.sql` and run it in the SQL Editor to build your tables and configure Row-Level Security (RLS).
5. **Create your Super Admin:**
   * Go to **Authentication -> Add User -> Create New User** in the Supabase Dashboard.
   * Create an account: `admin@stranx.com` / `Admin123!`.
   * Return to the **SQL Editor** and run this command to assign admin privileges:
     ```sql
     INSERT INTO public.user_roles (user_id, role)
     SELECT id, 'super_admin' FROM auth.users WHERE email = 'admin@stranx.com';
     ```

### Step 2: Grab your Environment Variables
From your Supabase Project Settings > API, copy the following keys:
1. **URL** (`NEXT_PUBLIC_SUPABASE_URL`)
2. **anon => public key** (`NEXT_PUBLIC_SUPABASE_ANON_KEY`)
3. **service_role => secret key** (`SUPABASE_SERVICE_ROLE_KEY`) - *Required for the Super Admin user management API.*

### Step 3: Deploy the Frontend to Vercel
1. Push this repository to a GitHub account.
2. Go to [Vercel](https://vercel.com/) and click **Add New Project**.
3. Import your GitHub repository.
4. Open the **Environment Variables** section in the Vercel deployment configuration, and add the three keys you copied above:
   * `NEXT_PUBLIC_SUPABASE_URL=your_url`
   * `NEXT_PUBLIC_SUPABASE_ANON_KEY=your_anon_key`
   * `SUPABASE_SERVICE_ROLE_KEY=your_service_role_key`
5. Click **Deploy**. Vercel will build and launch your application globally.

---

## 🔐 Logging In & Creating Users

Once deployed, visit your Vercel URL.
Log in using your master admin account: `admin@stranx.com` / `Admin123!`.

You will be routed to the `/admin` console. From the Admin Console, use the **User Management** panel to securely create the rest of your operation teams. Selecting a role in the UI will automatically set up their permissions and routing:

* **Super Admin:** Routes to `/admin`
* **WFM Manager:** Routes to `/wfm`
* **Database Team:** Routes to `/team/database`
* **Scrubbing Team:** Routes to `/team/scrub`
* **Tele-verification:** Routes to `/team/tv`
* **QC Team:** Routes to `/team/qc`
* **Delivery Team:** Routes to `/team/delivery`

## 🛡 Security Notes
The portal uses dynamic Edge Middleware to intercept every request, automatically verifying authentication, checking `user_roles`, and restricting based on allowed IPs mapped directly to your database.
