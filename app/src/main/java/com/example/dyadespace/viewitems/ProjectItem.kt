package com.example.dyadespace.viewitems


import android.view.RoundedCorner
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import coil.compose.AsyncImage
import com.example.dyadespace.classes.Projects
import com.example.dyadespace.classes.Tasks

@Composable
fun ProjectItem(p: Projects) {
    Card(
        modifier = Modifier
            .fillMaxWidth()
            .height(400.dp)
            .padding(horizontal = 16.dp, vertical = 16.dp),
        elevation = CardDefaults.cardElevation(4.dp),
        shape = RoundedCornerShape(25.dp)
    ) {





            Column(modifier = Modifier.padding(20.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
                        verticalArrangement = Arrangement.Center
            ) {

                AsyncImage(
                    model = p.photo_url?.let { "$it?type=image/jpeg" } ?: "",
                    contentDescription = "Project Image",
                    modifier = Modifier
                        .fillMaxWidth()
                        .height(200.dp)
                        .padding(end = 12.dp),
                    contentScale = ContentScale.Crop
                )

                Text(
                    text = p.name ?: "Unnamed Project",
                    style = MaterialTheme.typography.titleMedium
                )

                Text(
                    text = p.description ?: "",
                    style = MaterialTheme.typography.bodyMedium,
                    modifier = Modifier.padding(top = 6.dp)
                )

                Text(
                    text = "Address: ${p.address ?: "N/A"}",
                    style = MaterialTheme.typography.labelMedium,
                    modifier = Modifier.padding(top = 4.dp)
                )
            }

    }
}

@Preview(showBackground = true)
@Composable
fun ProjectItemPreview() {
    ProjectItem(
        Projects(
            id = "P123",
            name = "Office Renovation",
            description = "Renovating the office 3rd floor — electricians and drywall phase this week.",
            address = "Montreal QC",
            photo_url = "https://gpzpemmuoybkihvlfqxv.supabase.co/storage/v1/object/public/project_photos/images/1765305622455_asd.jpg" // change to real URL later
        )
    )
}

