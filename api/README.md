# Shri Krishna Goshala Mobile API Collection

This directory contains the complete Postman collection for the Shri Krishna Goshala mobile application APIs.

## 📁 Files

- `Shri_Krishna_Goshala_Mobile_API.postman_collection.json` - Complete Postman collection with all API endpoints

## 🚀 Quick Start

### 1. Import Collection
1. Open Postman
2. Click "Import" button
3. Select the `Shri_Krishna_Goshala_Mobile_API.postman_collection.json` file
4. Collection will be imported with all folders and requests

### 2. Environment Setup
Set up these environment variables in Postman:

| Variable | Description | Example |
|----------|-------------|---------|
| `base_url` | API base URL | `https://your-domain.com` |
| `jwt_token` | Authentication token | Set after login |
| `customer_id` | Sample customer ID | `1` |
| `product_id` | Sample product ID | `1` |

### 3. Authentication Flow
1. Use **Unified Login** from the 🔐 Authentication folder (supports both customers and delivery persons)
2. Copy the `jwt_token` from the response
3. Set it as the `jwt_token` environment variable
4. All subsequent requests will automatically use this token

**Note**: The unified login automatically detects user type based on credentials and returns the appropriate token.

## 📱 API Categories

### 🔐 Authentication (8 endpoints)
- **Unified signup/login** - Single endpoints for all user types
- Legacy customer signup/login (backward compatibility)
- Token refresh and regeneration

### 🏷️ Categories (5 endpoints)
- Product category management
- CRUD operations for categories

### 🥛 Products (6 endpoints)
- Product inventory management
- Low stock alerts
- Product CRUD operations

### 👥 Customers (5 endpoints)
- Customer profile management
- Location updates
- Settings management

### 📍 Customer Addresses (5 endpoints)
- Address management
- Default address setting
- Multiple address support

### 🛒 Orders (2 endpoints)
- Single-day order placement
- Order history retrieval

### 📅 Subscriptions (4 endpoints)
- Multi-day subscription management
- Recurring delivery setup

### 🚚 Delivery Assignments (8 endpoints)
- Delivery task management
- GPS-based nearest delivery
- Bulk completion support
- Real-time status updates

### 📦 Delivery Items (5 endpoints)
- Individual item management within deliveries
- Item addition/modification during delivery

### 📋 Delivery Schedules (5 endpoints)
- Delivery planning and scheduling
- Date-based filtering

### 📢 Advertisements (1 endpoint)
- Marketing content retrieval

### 🧾 Invoices (1 endpoint)
- Customer billing information

### 🏖️ Vacations (8 endpoints)
- Customer vacation management
- Delivery pause/resume functionality
- Impact preview with dry run

### ⚙️ Settings (15 endpoints)
- App configuration
- FAQ management
- Content management (Terms, Privacy)
- User preferences
- Address management via settings

### 🏦 Bank Details (1 endpoint)
- Payment information retrieval

### 📱 Legacy Deliveries (4 endpoints)
- Backward compatibility APIs
- Legacy mobile app support

### 📁 File Upload (2 endpoints)
- Image and document upload
- Folder-based organization

## 🔒 Authentication

All APIs use JWT Bearer token authentication:

```
Authorization: Bearer <jwt_token>
```

The collection is configured to automatically add this header using the `{{jwt_token}}` variable.

## 📝 Request Examples

### Unified Login (Phone)
```http
POST /api/v1/login
Content-Type: application/json

{
  "phone_number": "9876543210",
  "password": "securepassword123"
}
```

### Unified Login (Email)
```http
POST /api/v1/login
Content-Type: application/json

{
  "email": "user@example.com",
  "password": "securepassword123"
}
```

**Response for Customer:**
```json
{
  "token": "jwt_token_here",
  "refresh_token": "refresh_token_here",
  "token_expires_in": 86400,
  "refresh_token_expires_in": 604800,
  "user_type": "customer",
  "customer": {
    "id": 1,
    "name": "John Doe",
    "phone_number": "9876543210",
    "email": "john@example.com"
  }
}
```

**Response for Delivery Person:**
```json
{
  "token": "jwt_token_here",
  "refresh_token": "refresh_token_here",
  "token_expires_in": 86400,
  "refresh_token_expires_in": 604800,
  "user_type": "delivery_person",
  "user": {
    "id": 1,
    "name": "Delivery Person",
    "role": "delivery_person",
    "email": "delivery@example.com",
    "phone": "9876543211"
  }
}
```

### Unified Signup (Customer)
```http
POST /api/v1/signup
Content-Type: application/json

{
  "name": "John Doe",
  "email": "john.doe@example.com",
  "phone_number": "9876543210",
  "password": "securepassword123",
  "address": "123 Main Street, Bangalore, Karnataka 560001",
  "role": "customer"
}
```

### Unified Signup (Delivery Person)
```http
POST /api/v1/signup
Content-Type: application/json

{
  "name": "Delivery Person Name",
  "email": "delivery@example.com",
  "phone": "9876543211",
  "password": "deliverypass123",
  "role": "delivery_person"
}
```

**Signup Response Format:**
- Same as login response with `status: 201` (created)
- Automatically logs in user after successful registration
- Returns appropriate token based on user type
- Role parameter is optional (defaults to "customer")
- Supports: `customer`, `delivery_person`, `admin`

### Place Order
```http
POST /api/v1/place_order
Authorization: Bearer <jwt_token>
Content-Type: application/json

{
  "customer_id": 1,
  "items": [
    {
      "product_id": 1,
      "quantity": 2,
      "price": 55.0
    }
  ],
  "delivery_date": "2024-01-15",
  "delivery_time_slot": "morning"
}
```

### Complete Delivery
```http
POST /api/v1/delivery_assignments/1/complete
Authorization: Bearer <jwt_token>
Content-Type: application/json

{
  "payment_status": "paid",
  "payment_method": "cash",
  "amount_collected": 110.0,
  "notes": "Delivered successfully"
}
```

## 🏗️ API Architecture

### Base URL Structure
- **Production**: `https://your-production-domain.com`
- **Staging**: `https://your-staging-domain.com`
- **Development**: `http://localhost:3000`

### API Versioning
All mobile APIs are versioned under `/api/v1/`

### Response Format
```json
{
  "success": true,
  "data": {},
  "message": "Success message",
  "errors": []
}
```

### Error Handling
```json
{
  "success": false,
  "errors": ["Error message"],
  "message": "Operation failed"
}
```

## 🔧 Common Use Cases

### For Customer App:
1. **Authentication** → Customer signup/login
2. **Browse Products** → Get categories and products
3. **Place Orders** → Create single-day orders
4. **Manage Subscriptions** → Setup recurring deliveries
5. **Track Deliveries** → View delivery status
6. **Manage Profile** → Update settings and addresses
7. **Plan Vacations** → Pause deliveries during absence

### For Delivery Person App:
1. **Authentication** → Delivery person login
2. **View Assignments** → Get today's deliveries
3. **Navigate** → Start nearest delivery based on GPS
4. **Complete Deliveries** → Mark deliveries as completed
5. **Manage Items** → Add/modify delivery items
6. **Bulk Operations** → Complete multiple deliveries

### For Admin/Management:
1. **Product Management** → Add/update products and categories
2. **Customer Management** → Manage customer accounts
3. **Schedule Management** → Plan delivery routes
4. **Analytics** → View delivery and sales data

## 📊 Testing Scenarios

### Authentication Flow:
1. **Unified signup** → Auto-login → Get token (customer/delivery person)
2. **Unified login** → Get token (automatic user type detection)
3. Token refresh when expired

### Order Flow:
1. Browse categories and products
2. Add items to cart
3. Place order with delivery date
4. Track order status

### Delivery Flow:
1. Delivery person views assigned deliveries
2. Starts nearest delivery using GPS
3. Completes delivery with payment details
4. Bulk completes remaining deliveries

### Subscription Management:
1. Create daily/weekly subscription
2. Pause during vacation
3. Resume after vacation
4. Update quantity/frequency

## 🐛 Troubleshooting

### Common Issues:

**401 Unauthorized:**
- Check if JWT token is set correctly
- Verify token hasn't expired
- Use refresh token endpoint if needed

**400 Bad Request:**
- Validate request body format
- Check required fields
- Ensure proper data types

**404 Not Found:**
- Verify endpoint URL
- Check if resource exists
- Confirm API version

**500 Internal Server Error:**
- Check server logs
- Validate data integrity
- Contact development team

## 📞 Support

For API support and documentation:
- **Development Team**: Contact your development team
- **Documentation**: This README and inline Postman documentation
- **Bug Reports**: Use your project's issue tracking system

## 📝 Notes

- All timestamps are in ISO 8601 format
- Prices are in decimal format (e.g., 55.50)
- Phone numbers should include country code
- GPS coordinates use decimal degrees format
- File uploads support common image formats (JPG, PNG, etc.)

---

**Last Updated**: November 2024
**API Version**: v1
**Collection Version**: 1.0.0