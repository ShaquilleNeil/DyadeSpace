package com.example.dyadespace.viewitems


import android.view.RoundedCorner
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.animateContentSize
import androidx.compose.animation.expandVertically
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.shrinkVertically
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ArrowForward
import androidx.compose.material.icons.filled.ExpandCircleDown
import androidx.compose.material.icons.filled.ExpandLess
import androidx.compose.material.icons.filled.ExpandMore
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import androidx.navigation.NavController
import androidx.navigation.compose.rememberNavController
import androidx.test.espresso.base.Default
import coil.compose.AsyncImage
import com.example.dyadespace.classes.Projects
import com.example.dyadespace.classes.Tasks
import androidx.compose.runtime.getValue
import androidx.compose.runtime.setValue
import androidx.compose.ui.res.stringResource
import com.example.dyadespace.R


@Composable
fun ProjectItem(p: Projects, navController: NavController) {

    var projectexpanded by remember { mutableStateOf(false) }


    Card(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 8.dp)
            .animateContentSize(), // ⭐ allows expand/collapse
        shape = RoundedCornerShape(15.dp),
        elevation = CardDefaults.cardElevation(8.dp)
    ) {
        Column {

            // -------- COLLAPSED HEADER (ALWAYS VISIBLE) --------
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(16.dp)
                    .clickable { projectexpanded = !projectexpanded },
                verticalAlignment = Alignment.CenterVertically
            ) {
                Text(
                    text = p.name ?: "Unnamed Project",
                    style = MaterialTheme.typography.titleMedium
                )

                Spacer(modifier = Modifier.weight(1f))

                Surface(
                    shape = RoundedCornerShape(50),
                    color = Color(0xFF34D399)
                ) {
                    Text(
                        text = "IN PROGRESS",
                        modifier = Modifier.padding(horizontal = 10.dp, vertical = 4.dp),
                        style = MaterialTheme.typography.labelSmall,
                        color = Color.Black
                    )
                }

                Spacer(modifier = Modifier.width(8.dp))

                Icon(
                    imageVector =
                        if (projectexpanded)
                            Icons.Default.ExpandLess
                        else
                            Icons.Default.ExpandCircleDown,
                    contentDescription = null
                )
            }

            // -------- EXPANDED CONTENT --------
            AnimatedVisibility(
                visible = projectexpanded,
                enter = fadeIn() + expandVertically(),
                exit = fadeOut() + shrinkVertically()
            ) {
                Box(
                    modifier = Modifier
                        .fillMaxWidth()
                        .height(250.dp) // ONLY the expanded area gets height
                ) {

                    AsyncImage(
                        model = p.photo_url ?: "",
                        contentDescription = null,
                        contentScale = ContentScale.Crop,
                        modifier = Modifier.fillMaxSize()
                    )

                    Box(
                        modifier = Modifier
                            .fillMaxSize()
                            .background(
                                Brush.verticalGradient(
                                    listOf(
                                        Color.Transparent,
                                        Color.Black.copy(alpha = 0.7f)
                                    )
                                )
                            )
                    )

                    Column(
                        modifier = Modifier
                            .align(Alignment.BottomStart)
                            .padding(10.dp)
                    ) {
                        Text(
                            text = "${stringResource(R.string.location)} :",
                            style = MaterialTheme.typography.labelMedium,
                            color = Color.White,
                            maxLines = 2,
                            overflow = TextOverflow.Ellipsis
                        )
                        Text( text = p.address ?: "N/A", style = MaterialTheme.typography.labelSmall, color = Color(0xFF34D399) )

                        Spacer(Modifier.height(8.dp))

                        Button(
                            onClick = {
                                p.id?.let { navController.navigate("projectView/$it") }
                            },
                            shape = RoundedCornerShape(50),
                            colors = ButtonDefaults.buttonColors(
                                containerColor = Color.White.copy(alpha = 0.15f)
                            )
                        ) {
                            Text("View Details ", color = Color.White)
                            Icon(
                                imageVector = Icons.Default.ArrowForward,
                                contentDescription = "Person Icon",
                                modifier = Modifier.size(20.dp),
                                tint = Color.White
                            )
                        }
                    }
                }
            }
        }
    }

}





@Preview(showBackground = true)
@Composable
fun ProjectItemPreview() {
    val navController = rememberNavController()

    ProjectItem(
        p = Projects(
            id = "P123",
            name = "Office Renovation",
            description = "Renovating the office 3rd floor — electricians and drywall phase this week.",
            address = "Montreal QC",
            photo_url = "https://gpzpemmuoybkihvlfqxv.supabase.co/storage/v1/object/public/project_photos/images/1765305622455_asd.jpg"
        ),
        navController = navController
    )
}
