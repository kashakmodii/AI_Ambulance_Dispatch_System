# AI Ambulance Project

An emergency response mobile application built with **Flutter** that allows users to request the nearest ambulance in real time.  
The app integrates **Firebase Firestore** and **real-time location tracking** (without Google Maps API) to provide an efficient ambulance booking and management system.

---

## Features

-  **User Authentication**
  - Sign up and login using phone number.
  - Secure profile management.

-  **Live Location Tracking**
  - Captures the user’s current location.
  - Displays ambulance response and updates location dynamically.
  - Uses **Flutter Location package** instead of Google Maps API.

-  **Ambulance Request System**
  - Submit a request for an ambulance.
  - Store request details (name, mobile number, location) in Firebase.
  - Retrieve assigned ambulance details and show in map screen.

-  **Drawer with User Info**
  - Shows logged-in user’s **name** and **mobile number** (fetched from Firestore request).
  - Navigation to profile, settings, and logout.

-  **Notifications / Alerts**
  - Displays alert for nearest ambulance availability.
  - Can be extended to push notifications (Firebase Cloud Messaging).

---

## 🛠 Tech Stack

- **Flutter** (Dart)
- **Firebase**
  - Firestore (Database)
  - Authentication
  - Realtime Updates
- **Flutter Location Package** (for device location tracking)

---



